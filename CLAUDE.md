# Watch Tracker — Claude Rules

## Auto-commit after data.json edits

Whenever you update `data.json` (adding, removing, or updating a show), immediately run:

```bash
git add data.json && git commit -m "update: <short description of change>" && git push
```

Do this automatically — do not ask the user to run it.
