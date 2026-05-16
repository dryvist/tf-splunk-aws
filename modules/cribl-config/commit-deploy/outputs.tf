output "commit_sha" {
  description = "SHA of the commit produced this apply; useful as a depends_on / health indicator."
  value       = criblio_commit.this.items[0].commit
}
