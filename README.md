#Automate Cloudlets Edge Redirect
##Description
This project is to automate the Akamai Cloudlets Edge Redirects
##Usage
* Create new version based on current product version and add the new rules, then push to staging. In the job_file, add the redirect from_url and to_url, one job one line.
 ./auto_redirect.sh job_file

* Test the redirect in staging
 ./test_staging







