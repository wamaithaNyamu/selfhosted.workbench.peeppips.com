TODO:
1. Use pinned versions of the FE and BE
2. Improve docs for anyone running the bash script manually
3. Host the bashscript so we can end up with one curl command 
4. Bash script needs a loop that has licencing passed on and automatically generating the postgres password and auth password
5. [idea] still do auth from my server so we can keep emails working


### Pre requisites
Create a .env and add the following

```sh
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=workbench
POSTGRES_USER=workbench
POSTGRES_PASSWORD=workbench_password # supposed to be a super secret password
POSTGRES_SSLMODE=disable
DATABASE_URL=postgres://workbench:workbench_password@postgres:5432/workbench?sslmode=disable
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_ADDR=redis:6379
SERVER_PORT=8080
PORT=8080



```
### How to get started:
Give script necessary permissions
```sh
chmod +x deploy-workbench.sh
```
Run script that does blue green deployment
```sh
./deploy-workbench.sh
```

