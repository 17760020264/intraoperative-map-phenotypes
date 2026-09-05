# Public Release Checklist

Complete this checklist before making the repository public.

- [ ] The repository states INSPIRE **version 1.0** everywhere.
- [ ] No MOVER or INSPIRE source data are included.
- [ ] No patient- or operation-level derived files are included.
- [ ] No local absolute paths, credentials, usernames, tokens, or download commands are included.
- [ ] `config.local.json` is not tracked.
- [ ] `python -m pytest tests -q` passes.
- [ ] `python scripts/verify_reference_outputs.py` passes.
- [ ] `python scripts/audit_public_release.py` passes.
- [ ] `CITATION.cff` contains the final GitHub owner.
- [ ] The GitHub Actions workflow passes.
- [ ] Release `v1.0.0` is published and not subsequently moved.
- [ ] The archived release DOI is inserted into the manuscript and Data Sharing Statement.
