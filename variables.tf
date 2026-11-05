variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "in_toto_version" {
  type        = string
  default     = "3.1.0"
  description = "in-toto release to install from PyPI. Any other than 3.1.0 needs requirements to match."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.in_toto_version))
    error_message = "in_toto_version is a release number such as \"3.1.0\"."
  }
}

variable "requirements" {
  type        = string
  default     = null
  description = "Hash-locked pip requirements for in_toto_version, in place of the module's requirements.txt for 3.1.0. Every line pins one version with --hash=sha256 values."

  validation {
    condition     = var.requirements != null || var.in_toto_version == "3.1.0"
    error_message = "The module only carries requirements for in-toto 3.1.0. For another in_toto_version, pass requirements locked for it."
  }

  validation {
    condition     = var.requirements == null || (strcontains(coalesce(var.requirements, "-"), "in-toto==${var.in_toto_version}") && strcontains(coalesce(var.requirements, "-"), "--hash=sha256:"))
    error_message = "requirements must pin in-toto==${var.in_toto_version} and carry --hash=sha256 values, as uv pip compile --generate-hashes or pip-compile --generate-hashes write them."
  }
}
