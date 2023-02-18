# PGO - Crunchy Postgres Operator

Operator for deploying and managing Postgres clusters developed by Crunchy Data.

Github: https://github.com/CrunchyData/postgres-operator
Documentation: https://access.crunchydata.com/documentation/postgres-operator/latest

## Installation

Uses kustomize directories provided by Crunchy at https://github.com/CrunchyData/postgres-operator-examples.

## Monitoring

See `podmonitor.yaml`

## Importing a database dump

While it's possible to declaratively configure crunchy postgres clusters to import data using a few different strategies, importing a database dump into an already existing postgres database can be a more straight forward alternative.

First get a database dump to restore. Eg. from Heroku:

```
heroku pg:backups -a <app> # find ID of dump you want to import
heroku pg:backups:url <backup-id> -a <app> # get backup URL

k playground worker-1 # open a shell in the kubernetes kluster
wget <backup-url> -O dump.sql # download the dump (only wget seems to work, curl corrupts the dump)
```

Now you can import the dump using `pg_restore`:

```
APPLICATION=<app-name>
pg_restore --verbose --clean --no-acl --no-owner -j 32 -h $APPLICATION-primary.default.svc -U $APPLICATION -d $APPLICATION dump.sql
```

## Failover

### Permanent Node failure

A node is taken out eg. due to a hardware failure to the point where it can't be rebooted.

In this scenario we expect any primary databases on the broken node to have automatically failed over to secondary replicas. However we will find that Kubernetes is eager to see the node back online, and pods will be in waiting indefinitely for the node to come back to be able to reboot (assuming we're using local storage, preventing pods from being rescheduled to other nodes).

To gracefully get rid of the broken node the first step is to Delete it from Kubernetes (ie. `kubectl delete node <node-name>`). This will allow the stateful sets to try to reschedule elsewhere which will now fail since node affinity with the local storage persistent volume will never be resolved.

To get rid of the failing replica set we can now reduce the replica count in the PGO cluster YAML. Immediately after we can add back the replica count and a new stateful set can be created on a new node.

The only trash to take out at this point should be the old persistent volume which should be listed as Status: Released.
