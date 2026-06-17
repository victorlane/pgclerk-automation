# production inventories

One directory per customer:

```
production/
  acme/
    hosts.ini
    group_vars/
      all.yml
      patroni.yml
    host_vars/
      acme-pg-01.yml
  globex/
    hosts.ini
    …
```

Customer inventories are encrypted with `git-crypt`. Don't add them
unencrypted. The operator app discovers customers by listing this
directory and matching slugs against the `customers` table.
