/*
Copyright 2020 The Crossplane Authors.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package instana

import (
	"context"

	"github.com/pkg/errors"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/util/workqueue"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"

	"github.com/crossplane/crossplane-runtime/pkg/event"
	"github.com/crossplane/crossplane-runtime/pkg/logging"
	"github.com/crossplane/crossplane-runtime/pkg/ratelimiter"
	"github.com/crossplane/crossplane-runtime/pkg/reconciler/managed"
	"github.com/crossplane/crossplane-runtime/pkg/resource"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/jianh619/provider-instana/apis/instana/v1alpha1"
	apisv1alpha1 "github.com/jianh619/provider-instana/apis/v1alpha1"
)

const (
	errNotInstana   = "managed resource is not a Instana custom resource"
	errTrackPCUsage = "cannot track ProviderConfig usage"
	errGetSecret    = "cannot get Secret"
	errGetPC        = "cannot get ProviderConfig"
	errGetCreds     = "cannot get credentials"
	errNewClient    = "cannot create new Service"
)

// A NoOpService does nothing.
type NoOpService struct{}

var (
	newNoOpService = func(_ []byte) (interface{}, error) { return &NoOpService{}, nil }
)

// Setup adds a controller that reconciles Instana managed resources.
func Setup(mgr ctrl.Manager, l logging.Logger, rl workqueue.RateLimiter) error {
	name := managed.ControllerName(v1alpha1.InstanaGroupKind)
	logger := l.WithValues("controller", name)

	o := controller.Options{
		RateLimiter: ratelimiter.NewDefaultManagedRateLimiter(rl),
	}

	r := managed.NewReconciler(mgr,
		resource.ManagedKind(v1alpha1.InstanaGroupVersionKind),
		managed.WithExternalConnecter(&connector{
			logger: logger,
			kube:   mgr.GetClient(),
			usage:  resource.NewProviderConfigUsageTracker(mgr.GetClient(), &apisv1alpha1.ProviderConfigUsage{}),
		}),
		managed.WithLogger(l.WithValues("controller", name)),
		managed.WithRecorder(event.NewAPIRecorder(mgr.GetEventRecorderFor(name))))

	return ctrl.NewControllerManagedBy(mgr).
		Named(name).
		WithOptions(o).
		For(&v1alpha1.Instana{}).
		Complete(r)
}

// A connector is expected to produce an ExternalClient when its Connect method
// is called.
type connector struct {
	logger logging.Logger
	kube   client.Client
	usage  resource.Tracker
}

// Connect typically produces an ExternalClient by:
// 1. Tracking that the managed resource is using a ProviderConfig.
// 2. Getting the managed resource's ProviderConfig.
// 3. Getting the credentials specified by the ProviderConfig.
// 4. Using the credentials to form a client.
func (c *connector) Connect(ctx context.Context, mg resource.Managed) (managed.ExternalClient, error) {
	cr, ok := mg.(*v1alpha1.Instana)
	if !ok {
		return nil, errors.New(errNotInstana)
	}
	logger := c.logger.WithValues("request", cr.Name)

	logger.Info("Connecting")

	if err := c.usage.Track(ctx, mg); err != nil {
		return nil, errors.Wrap(err, errTrackPCUsage)
	}

	pc := &apisv1alpha1.ProviderConfig{}
	if err := c.kube.Get(ctx, types.NamespacedName{Name: cr.GetProviderConfigReference().Name}, pc); err != nil {
		return nil, errors.Wrap(err, errGetPC)
	}

	cd := pc.Spec.Credentials
	data, err := resource.CommonCredentialExtractor(ctx, cd.Source, c.kube, cd.CommonCredentialSelectors)
	if err != nil {
		return nil, errors.Wrap(err, errGetCreds)
	}

	if data == nil || len(data) == 0 {
		return nil, errors.New("The secret is not ready yet")
	}

	clientConfig, err := clientcmd.RESTConfigFromKubeConfig(data)

	kubeClient, err := kubernetes.NewForConfig(clientConfig)
	if err != nil {
		panic(err)
	}

	return &external{
		c.logger,
		c.kube,
		kubeClient,
		pc.Spec.Credentials.SecretRef.Name,
		pc.Spec.Credentials.SecretRef.Namespace,
	}, nil
}

// An ExternalClient observes, then either creates, updates, or deletes an
// external resource to ensure it reflects the managed resource's desired state.
type external struct {
	// A 'client' used to connect to the external resource API. In practice this
	// would be something like an AWS SDK client.
	logger           logging.Logger
	kube             client.Client
	rkube            *kubernetes.Clientset
	rClusterSecretN  string
	rClusterSecretNS string
}

func (e *external) Observe(ctx context.Context, mg resource.Managed) (managed.ExternalObservation, error) {
	cr, ok := mg.(*v1alpha1.Instana)
	if !ok {
		return managed.ExternalObservation{}, errors.New(errNotInstana)
	}

	// These fmt statements should be removed in the real implementation.
	e.logger.Info("Observing: " + cr.ObjectMeta.Name)
	//Check if there's available cluster
	err := e.observeInstana(ctx)
	if err != nil {
		return managed.ExternalObservation{
			ResourceExists: false,
		}, nil
	}

	return managed.ExternalObservation{
		// Return false when the external resource does not exist. This lets
		// the managed resource reconciler know that it needs to call Create to
		// (re)create the resource, or that it has successfully been deleted.
		ResourceExists: true,

		// Return false when the external resource exists, but it not up to date
		// with the desired managed resource state. This lets the managed
		// resource reconciler know that it needs to call Update.
		ResourceUpToDate: true,

		// Return any details that may be required to connect to the external
		// resource. These will be stored as the connection secret.
		ConnectionDetails: managed.ConnectionDetails{},
	}, nil
}

func (e *external) Create(ctx context.Context, mg resource.Managed) (managed.ExternalCreation, error) {
	cr, ok := mg.(*v1alpha1.Instana)
	if !ok {
		return managed.ExternalCreation{}, errors.New(errNotInstana)
	}

	e.logger.Info("Create instana job : " + cr.Name)
	e.installInstana(ctx, cr)
	return managed.ExternalCreation{
		// Optionally return any details that may be required to connect to the
		// external resource. These will be stored as the connection secret.
		ConnectionDetails: managed.ConnectionDetails{},
	}, nil
}

func (e *external) Update(ctx context.Context, mg resource.Managed) (managed.ExternalUpdate, error) {
	cr, ok := mg.(*v1alpha1.Instana)
	if !ok {
		return managed.ExternalUpdate{}, errors.New(errNotInstana)
	}

	e.logger.Info("Updating: " + cr.Name)

	return managed.ExternalUpdate{
		// Optionally return any details that may be required to connect to the
		// external resource. These will be stored as the connection secret.
		ConnectionDetails: managed.ConnectionDetails{},
	}, nil
}

func (e *external) Delete(ctx context.Context, mg resource.Managed) error {
	cr, ok := mg.(*v1alpha1.Instana)
	if !ok {
		return errors.New(errNotInstana)
	}

	e.logger.Info("Destroy cluster : " + cr.Name)

	return nil
}

func (e *external) observeInstana(ctx context.Context) error {
	e.logger.Info("Checking if instana is available in current cluster")
	installJob := &batchv1.Job{}

	err := e.kube.Get(ctx, client.ObjectKey{
		Namespace: e.rClusterSecretNS,
		Name:      "instana-" + e.rClusterSecretN,
	}, installJob)
	if err != nil {
		return err
	}
	e.verifyInstana(ctx)
	return nil
}

func (e *external) verifyInstana(ctx context.Context) error {
	e.logger.Info("Start Verifying Instana installing ")
	_, err := e.rkube.AppsV1().Deployments("instana-core").Get(context.TODO(), "acceptor", metav1.GetOptions{})
	if err != nil {
		e.logger.Info("Deployment acceptor , Namespace instana-core  , is not available yet")
		return err
	}
	_, err = e.rkube.AppsV1().Deployments("instana-core").Get(context.TODO(), "ingress-core", metav1.GetOptions{})
	if err != nil {
		e.logger.Info("Deployment ingress-core , Namespace instana-core  , is not available yet")
		return err
	}
	_, err = e.rkube.AppsV1().Deployments("instana-units").Get(context.TODO(), "ingress", metav1.GetOptions{})
	if err != nil {
		e.logger.Info("Deployment ingress , Namespace ingress-units  , is not available yet")
		return err
	}
	e.logger.Info("Instana installing completed successfully ")
	return nil
}

func (e *external) installInstana(ctx context.Context, cr *v1alpha1.Instana) error {
	e.logger.Info("Creating install installing job")
	installJob := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "instana-" + e.rClusterSecretN,
			Namespace: e.rClusterSecretNS,
		},
		Spec: batchv1.JobSpec{
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "instana-install",
							Image: "quay.io/hjwilson19560/instana-install:latest",
							Command: []string{
								"/root/instana/install.sh",
							},
							Env: []corev1.EnvVar{
								{
									Name:  "INSTANA_DB_HOST",
									Value: cr.Spec.ForProvider.NFSServerHost,
								},
								{
									Name:  "INSTANA_VERSION",
									Value: cr.Spec.ForProvider.InstanaVersion,
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      "kubeconfig",
									MountPath: "/root/.kube",
								},
								{
									Name:      "settings",
									MountPath: "/root/instana/conf",
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "kubeconfig",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName: e.rClusterSecretN,
									Items: []corev1.KeyToPath{
										{
											Key:  "credentials",
											Path: "config",
										},
									},
								},
							},
						},
						{
							Name: "settings",
							VolumeSource: corev1.VolumeSource{
								ConfigMap: &corev1.ConfigMapVolumeSource{
									LocalObjectReference: corev1.LocalObjectReference{
										Name: cr.Spec.ForProvider.SettingsConfigmap.Name,
									},
								},
							},
						},
					},
					RestartPolicy: corev1.RestartPolicyNever,
				},
			},
		},
	}
	err := e.kube.Create(ctx, installJob)
	if err != nil {
		e.logger.Info("Create Job error , namespace : crossplane-system , name: instana-install " + err.Error())
		return err
	}
	e.logger.Info("instana job created successfully ")
	return nil
}

