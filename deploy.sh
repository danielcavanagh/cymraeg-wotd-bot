#!/bin/sh
docker build -t danielcavanagh/cymraeg-wotd-bot .
docker push danielcavanagh/cymraeg-wotd-bot
hyper stop cwotd
hyper rm cwotd
hyper rmi danielcavanagh/cymraeg-wotd-bot
hyper pull danielcavanagh/cymraeg-wotd-bot
hyper run --size s1 --env-file docker.env -d --name cwotd danielcavanagh/cymraeg-wotd-bot
