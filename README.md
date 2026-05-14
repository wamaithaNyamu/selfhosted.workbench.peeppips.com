TODO:
1. Use pinned versions of the FE and BE
2. Improve docs for anyone running the bash script manually
3. Host the bashscript so we can end up with one curl command 
4. Bash script needs a loop that has licencing passed on and automatically generating the postgres password and auth password
5. [idea] still do auth from my server so we can keep emails working


### How to get started:
Give script necessary permissions
```sh
chmod +x deploy-workbench.sh
```
Run script that does blue green deployment
```sh
./deploy-workbench.sh
```