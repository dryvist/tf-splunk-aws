output "commit_sha" {
  description = "SHA of the commit produced this apply; useful as a depends_on / health indicator."
  value       = data.criblio_config_version.post_commit.items[0]
}
