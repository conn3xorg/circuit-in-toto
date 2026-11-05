# Facts give each host's distribution: Debian and Ubuntu need python3-venv,
# and a host this circuit wasn't tested on stops at plan.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = (self.os_id == "ubuntu" && self.os_version == "24.04") || (self.os_id == "debian" && self.os_version == "13") || (self.os_id == "rocky" && startswith(self.os_version, "10.")) || (self.os_id == "fedora" && self.os_version == "45")
      error_message = "Host ${each.key} runs ${self.os_id} ${self.os_version}. This circuit supports Ubuntu 24.04, Debian 13, Rocky Linux 10 and Fedora 45."
    }
  }
}

locals {
  venv         = "/opt/in-toto/${var.in_toto_version}"
  lock         = "/opt/in-toto/${var.in_toto_version}.requirements.txt"
  installed    = "${local.venv}/.conn3x-installed"
  requirements = var.requirements != null ? var.requirements : file("${path.module}/requirements.txt")
  commands     = ["in-toto-run", "in-toto-record", "in-toto-verify", "in-toto-sign", "in-toto-match-products", "in-toto-mock"]
}

circuit "in_toto" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "python" {
    package {
      name = "python3"
    }
  }

  # Debian and Ubuntu split venv and pip's bundled wheel out of python3. The
  # Red Hat family ships them with it.
  step "venv_support" {
    package {
      name = data.conn3x_host.facts[each.key].os_family == "debian" ? "python3-venv" : "python3"
    }
  }

  # A venv of its own, so in-toto's pins never meet the distribution's
  # Python packages. The check runs pip, so a venv left broken by an upgrade
  # to a new Python minor release is built again from scratch.
  step "venv" {
    command {
      command = "/usr/bin/python3 -m venv --clear '${local.venv}'"
      unless  = "'${local.venv}/bin/python' -m pip --version >/dev/null 2>&1"
    }
  }

  step "requirements" {
    file {
      path    = local.lock
      content = local.requirements
    }
  }

  # Every file pip installs has to match a hash in the requirements, and
  # only wheels are accepted, so nothing's build code runs. The copy beside
  # the venv records which requirements it holds; the trigger makes the
  # apply check again after a new file lands.
  step "install" {
    command {
      command  = "'${local.venv}/bin/python' -m pip install --quiet --disable-pip-version-check --no-deps --require-hashes --only-binary :all: -r '${local.lock}' && cp '${local.lock}' '${local.installed}'"
      unless   = "cmp -s '${local.lock}' '${local.installed}' && '${local.venv}/bin/python' -m pip check >/dev/null 2>&1"
      triggers = { requirements = conn3x_file.in_toto__requirements[each.key].revision }
    }
  }

  step "link" {
    for_each = toset(local.commands)
    link {
      path   = "/usr/local/bin/${item.value}"
      target = "${local.venv}/bin/${item.value}"
    }
  }
}
