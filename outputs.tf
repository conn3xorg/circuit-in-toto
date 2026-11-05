output "venv" {
  description = "The virtual environment in-toto is installed in, on each host."
  value       = local.venv
}

output "commands" {
  description = "The in-toto commands linked into /usr/local/bin."
  value       = [for c in local.commands : "/usr/local/bin/${c}"]
}

output "version" {
  description = "The in-toto release installed."
  value       = var.in_toto_version
}
