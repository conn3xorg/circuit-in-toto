variable "port" {
  type    = number
  default = 2222
}

# CI sets these to install an older in-toto first, then upgrades to the
# circuit's own pin by applying again without them.
variable "in_toto_version" {
  type    = string
  default = null
}

variable "requirements_file" {
  type    = string
  default = null
}

module "in_toto" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
  in_toto_version      = var.in_toto_version
  requirements         = var.requirements_file == null ? null : file(var.requirements_file)
}

output "commands" {
  value = module.in_toto.commands
}
