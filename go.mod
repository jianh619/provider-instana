module github.com/crossplane/provider-template

go 1.13

require (
	github.com/crossplane/crossplane-runtime v0.13.0
	github.com/crossplane/crossplane-tools v0.0.0-20201201125637-9ddc70edfd0d
	github.com/crossplane/provider-aws v0.17.0
	github.com/google/go-cmp v0.5.2
	github.com/pkg/errors v0.9.1
	golang.org/x/crypto v0.0.0-20201002170205-7f63de1d35b0
	gopkg.in/alecthomas/kingpin.v2 v2.2.6
	k8s.io/api v0.20.1
	k8s.io/apimachinery v0.20.1
	k8s.io/client-go v0.20.1
	sigs.k8s.io/controller-runtime v0.8.0
	sigs.k8s.io/controller-tools v0.4.0
)
