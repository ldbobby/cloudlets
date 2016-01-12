#!/bin/bash
# Cloudlets URL redirects automation written by Jackie Chen
# 08/12/2015 - Version 1.0

# Python version
MYPYTHON="python2.7"

# Cloudlets API credential
HEADER="import Cloudlets; s = Cloudlets.client(\"$CLD_BASEURL\",\"$CLD_CLIENTTOKEN\",\"$CLD_CLIENTSECRET\",\"$CLD_ACCESSTOKEN\")"

# Mail Receiver
RECEIVER="admin@domain.com"

# List cloudlets policy ID
list_policy_id(){
	echo ""
	echo "Downloading policy ID..."
	# Replace XXXXXX with your group ID
	$MYPYTHON -c "$HEADER; print s.listPolicies('XXXXXX')" | jq -r '.[] | "\(.name) \(.policyId)"' | sort > .temp.policy_ids
	#cat .temp.policy_ids
}

# Read redirects job queue
read_open_jobs()
{
	# Use local file for version 1.0
	if [ "$1" == "" ]
	then
		echo "Error: You need to provide a file with redirects request, for example: ./auto_redirect.sh redirect_file"
		echo ""
		exit 1
	fi
	sed -i '/^$/d' $1
	cat $1 > .temp.open_jobs

	# Validation
	TOTAL=`cat .temp.open_jobs | wc -l`
	echo There are $TOTAL open jobs in the queue.
	if [ $TOTAL -lt 1 ]; then exit 1; fi
	for (( c=1; c<=$TOTAL; c++  ))
	do
		OPENJOB=$(sed -n ${c}p .temp.open_jobs)
		url_check $OPENJOB
	done
}

url_check()
{
	FROM_URL=$1
	TO_URL=$2
	if [ ! $(echo $FROM_URL | /bin/grep -i ^http)  ]; then echo "Error: URL should start with http:// - FROM_URL: $FROM_URL"; exit 1; fi
	if [ -z $(echo $FROM_URL | cut -d "/" -f4)  ]; then echo "Error: URL should have a path after the host - FROM_URL: $FROM_URL"; exit 1; fi
	if [ ! $(echo $TO_URL | /bin/grep -i ^http)  ]; then echo "Error: URL should start with http:// - TO_URL: $TO_URL"; exit 1; fi
}

create_new_version()
{
	echo ""
	echo ">>>>>>>>>> Creating new version policy based on $PRODPOLICYVERSION..."
	$MYPYTHON -c "$HEADER; print s.createPolicyVersion('$POLICYID', '$PRODPOLICYVERSION', '.temp.$POLICYID.policyfile', '$VERNOTES')" > .temp.$POLICYID.newversion
	#cat .temp.$POLICYID.newversion
	NEWVERSION=`cat .temp.$POLICYID.newversion | jq -r .version`
	echo The new version is $NEWVERSION
}

activate_version()
{
	echo ""
	# POLICYENV can only be staging or prod
	POLICYENV=$1
	echo ">>>>>>>>>> Activating version $NEWVERSION of $POLICYNAME ($POLICYID) in $POLICYENV"
	$MYPYTHON -c "$HEADER; print s.activateVersion('$POLICYID','$NEWVERSION', '$POLICYENV')" > .temp.$POLICYID.$1
	cat .temp.$POLICYID.$1
	echo "------------------------------------------------------" >> .temp.$POLICYID.$1
	echo "Added the following redirects" >> .temp.$POLICYID.$1
	echo "------------------------------------------------------" >> .temp.$POLICYID.$1
	cat .temp.job.$POLICYID.$POLICYNAME >> .temp.$POLICYID.$1
	mail -s "`logname` pushed $POLICYNAME version $NEWVERSION to $1" $RECEIVER < .temp.$POLICYID.$1
}

download_policy()
{
	echo "Downloading policy from production version $PRODPOLICYVERSION..."
	$MYPYTHON -c "$HEADER; print s.getPolicyVersion('$POLICYID','$PRODPOLICYVERSION')" > .temp.$POLICYID.policy
	cp -f .temp.$POLICYID.policy .temp.$POLICYID.policy.old
	mv .temp.$POLICYID.policy .temp.$POLICYID.policy.new
}

add_policy()
{
	$MYPYTHON -c "$HEADER; s.addRule('$MERGEDRULES','$NEWRULE')"
}

check_policy_status()
{
	$MYPYTHON -c "$HEADER; print s.getPolicy('$POLICYID')" | jq -r '.activations[] | "\(.network) \(.policyInfo.status) \(.policyInfo.version)"'  > .temp.$POLICYID.status
	STAGPOLICYSTATUS=`cat .temp.$POLICYID.status | grep staging | awk {'print $2'}`
	STAGPOLICYVERSION=`cat .temp.$POLICYID.status | grep staging | awk {'print $3'}`
	PRODPOLICYSTATUS=`cat .temp.$POLICYID.status | grep prod | awk {'print $2'}`
	PRODPOLICYVERSION=`cat .temp.$POLICYID.status | grep prod | awk {'print $3'}`
	echo "STAGING: status-${STAGPOLICYSTATUS}, version-${STAGPOLICYVERSION}"
	echo "PRODUCTION: status-${PRODPOLICYSTATUS}, version-${PRODPOLICYVERSION}"
	if [ "$PRODPOLICYVERSION" == "0" ]
	then
		echo "0 means no production version yet, force to use version 1"
	        PRODPOLICYVERSION=1
	fi
}

categorize_job()
{
	for (( n=1; n<=$TOTAL; n++ ))
	do
		echo Reading job $n of $TOTAL...
		JOB=$(sed -n ${n}p .temp.open_jobs)
		# Modify following baesd on your policy naming convention
		POLICYNAME=$(echo "$JOB" | cut -d' ' -f1 | cut -d'/' -f3 | cut -d'.' -f1-2 | tr '.' '_')"_prod"
		POLICYID=$(cat .temp.policy_ids | grep $POLICYNAME | cut -d' ' -f2)
		if [ -z $POLICYID ]
		then
			echo Can not find policy ID for $POLICYNAME
			# set status as error
			continue
		else
			echo JOB FROM TO: $JOB
			echo POLICY NAME ID: $POLICYNAME $POLICYID
			echo $JOB >> .temp.job.$POLICYID.$POLICYNAME
		fi
	done
}

process_job()
{
	echo ""
	for site in `ls .temp.job.*`
	do
		SUBTOTAL=`cat $site | wc -l`
		POLICYID=`echo $site | cut -d'.' -f4`
		POLICYNAME=`echo $site | cut -d'.' -f5`
		# Checking if any previous pending configurations
		ls | grep ^staging.$POLICYID | grep -v test
		if [ $? -eq 0 ]
		then
			echo "Quit, as there is a pending configuration needs to be tested out first"
			continue
		fi
		echo ""
		echo "*********************************************************"
		echo Working on $POLICYNAME $POLICYID
		check_policy_status
		# Skip if there is a pending status
		if [ $STAGPOLICYSTATUS == "pending" ] || [ $PRODPOLICYSTATUS == "pending" ]
		then
			echo "The configuration is in pending status, skip this job for now"
			continue
		fi
		download_policy
		for (( m=1; m<=$SUBTOTAL; m++ ))
		do
			echo ""
			echo ">>>>>>>>>> Processing job $m of $SUBTOTAL for $POLICYNAME"
			JOB=$(sed -n ${m}p $site)
			FROMURL=`echo $JOB | awk {'print $1'}`
			TOURL=`echo $JOB | awk {'print $2'}`
			FROMPATH="${FROMPATH}`echo $FROMURL | cut -d '/' -f4-`,"
			echo FROM_URL: $FROMURL
			echo TO_URL: $TOURL
			$MYPYTHON -c "$HEADER; print s.createRule('$FROMURL', '$TOURL')" > .temp.$POLICYID.$m
			echo "Merging following policy..."
			cat .temp.$POLICYID.$m | jq -r .
			jq -s '.[0] as $o1 | .[1] as $o2 | ($o1 + $o2) | .matchRules = ($o1.matchRules + $o2.matchRules)' .temp.$POLICYID.policy.new .temp.$POLICYID.$m > .temp.$POLICYID.policy.temp
			mv .temp.$POLICYID.policy.temp .temp.$POLICYID.policy.new
		done
		UPDATES="`cat .temp.$POLICYID.policy.new | jq -r .matchRules`"
		echo $UPDATES > .temp.$POLICYID.policyfile
		VERNOTES=", added: $FROMPATH"
		create_new_version
		activate_version staging
		# Create pending job for testing staging later
		cp .temp.job.$POLICYID.$POLICYNAME staging.$POLICYID.$POLICYNAME.$NEWVERSION.$PRODPOLICYVERSION
	done
}

# Main function
clear && rm -rf .temp.*
read_open_jobs $1
list_policy_id
categorize_job
process_job
