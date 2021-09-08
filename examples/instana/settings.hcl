# <1>
download_key   = "qUMhYJxjSv6uZh2SyqTEnw" # This will be provided to you as part of our licensing flow
sales_key      = "pgABSBp_SnqIr5oMD68HoQ" # This will be provided to you as part of our licensing flow
base_domain    = "in-kind-kind.fyre.ibm.com" # base domain under which the login of instana will be reachable
core_name      = "instana-core"                 # It is possible to run multiple cores, so provide a good name for this installation
profile        = "small"                        # Sizing of instana: small/large/xlagre/xxlarge
admin_password = "passw0rd" # Password the initial admin user will have
token_secret   = "randomstring"              # Seed for creating crypto tokens, pick a random 12 char string
dhparams       = "dhparam.pem"                 # File containing Diffie-Hellman params
tls_crt_path   = "tls.crt"                      # SSL Cert used for publicly reachable endpoints of Instana
tls_key_path   = "tls.key"                      # SSL Key used for publicly reachable endpoints of Instana
license        = "license"                      # Location of the downloaded license file

ingress "agent-ingress" {                      # This block defines the public reachable name where the agents will connect
  hostname = "in-kind-kind.fyre.ibm.com"
  port     = 8600
}

email {                                        # configure this so instana can send alerts and invites
  user = "<user_name>>"
  password = "<user_password>>"
  host = "<smtp_host_name>"
}

units "prod" {                                 # This block defines a tenant unit named prod associated with the tenant instana
    tenant_name       = "instana"
    initial_agent_key = "qUMhYJxjSv6uZh2SyqTEnw"
    profile           = "small"
}

#units "dev" {                                  # This block defines a tenant unit named dev associated with the tenant instana
#    tenant_name       = "instana"
#    initial_agent_key = "<provided>"
#    profile           = "small"
#}

#features "a_feature" = {                       # Feature flags can be enabled/disabled
#    enabled = false
#}

#toggles "toggle_name" = {                      # Toggles are config values that can be overridden
#   value = "toggle_value"
#}

spans_location {                               # Spans can be stored in either s3 or on disk, this is an s3 example
    persistent_volume {                            # Use a persistent volume for raw-spans persistence
        volume_name = "raw-spans"             # Name of the persisten volume to be used
        storage_class = "nfs-client"           # Storage class to be used
    }
#  s3 {
#    storage_class           = "STANDARD"
#    access_key              = "access_key"
#    secret_key              = "secret_key"
#    endpoint                = "storage.googleapis.com"
#    region                  = "europe-west4"
#    bucket                  = "raw-spans"
#    prefix                  = "selfhosted"
#    storage_class_long_term = "STANDARD"
#    bucket_long_term        = "raw-spans"
#    prefix_long_term        = "selfhosted"
#  }
}

databases "cassandra"{                        # Database definitions, see below the code block for a detailed explanation.
  nodes = ["9.112.255.99"]
}

databases "cockroachdb"{
  nodes = ["9.112.255.99"]
}

databases "clickhouse"{
  nodes = ["9.112.255.99"]
}

databases "elasticsearch"{
  nodes = ["9.112.255.99"]
#  cluster_name = "onprem_onprem"
}

databases "kafka"{
  nodes = ["9.112.255.99"]
}

databases "zookeeper"{
  nodes = ["9.112.255.99"]
}

