#!/bin/bash
# Test Cloudlets URL redirects in staging written by Jackie Chen
# 12/01/2016 - Version 1.0

# Notes: This script does not work behind proxy, as it needs to spoof the hosts file to test change in staging.

# Python version
MYPYTHON="python2.7"

# Cloudlets API credential
HEADER="import Cloudlets; s = Cloudlets.client(\"$CLD_BASEURL\",\"$CLD_CLIENTTOKEN\",\"$CLD_CLIENTSECRET\",\"$CLD_ACCESSTOKEN\")"

# Test URL redirect
REDIRECT="import requests,sys; fromurl = sys.argv[1]; tourl = sys.argv[2]; response = requests.get(fromurl); print('0' if tourl == response.url else '1')"

# Mail Receiver
RECEIVER="admin@domain.com"

add_spoof_host()
{
	echo ""
	echo "Spoofing host file to test staging"
	STAGINGHOST=$(dig +short www.servers.edgesuite-staging.net | sort | head -1)
	sudo bash -c "echo '###spoofing_start###' >> /etc/hosts"
	sudo bash -c "echo $STAGINGHOST	www.server1.com >> /etc/hosts"
	sudo bash -c "echo $STAGINGHOST	www.server2.com >> /etc/hosts"
	sudo bash -c "echo $STAGINGHOST www.server3.com >> /etc/hosts"
	sudo bash -c "echo '###spoofing_end###' >> /etc/hosts"
}

remove_spoof_host()
{
	echo ""
	echo "Removing spoof from host file"
	STARTLINE=$(grep -n "###spoofing_start###" /etc/hosts | cut -d":" -f1)
	ENDLINE=$(grep -n "###spoofing_end###" /etc/hosts | cut -d":" -f1)
	sudo bash -c "sed -i $STARTLINE,${ENDLINE}d /etc/hosts"
}

read_pending_configurations()
{
	echo "Checking any pending configurations..."
	ls | grep ^staging | grep -v test
	if [ $? -ne 0 ]; then echo "No pending configurations in staging!"; exit 1; fi
	TOTAL=$(ls staging.* | grep -v test | wc -l)
	echo "There are $TOTAL pending configurations for testing in staging"
}

test_redirect()
{
	for site in `ls staging.* | grep -v test`
	do
		echo ""
		echo ">>>>>>>>>> Processing $site"
		n=0
		POLICYID=$(echo $site  | cut -d'.' -f2)
		POLICYNAME=$(echo $site  | cut -d'.' -f3)
		NEWVERSION=$(echo $site  | cut -d'.' -f4)
		OLDPRODVERSION=$(echo $site  | cut -d'.' -f5)
		check_prod_version
		SUBTOTAL=$(cat $site | wc -l)
		for (( j=1; j<=$SUBTOTAL; j++ ))
		do
			JOB=$(sed -n ${j}p $site)
			echo ""
			echo Testing redirect: $JOB
			RETURN=$($MYPYTHON -c "$REDIRECT" $JOB)
			echo "Result: $RETURN (0-passed, 1-failed)"
			if [ $RETURN == '0' ]; then echo $JOB PASSED >> $site.test_result; fi
			if [ $RETURN == '1' ]; then echo $JOB FAILED >> $site.test_result; fi
			let n=$n+$RETURN
		done
		#echo n is $n
		TESTRETURN="Test failed:"
		if [ $n -eq 0 ]
	   	then
			TESTRETURN="Test passed:"
			echo ""
			echo "Test is passed :)"
			cat $site.test_result
			# Check the before and after production version
			if [ "$OLDPRODVERSION" != "$NEWPRODVERSION" ]
			then
				echo ""
				echo "Abort activating prod of $POLICYNAME, as production version has changed while testing staging: old-$OLDPRODVERSION, new-$NEWPRODVERSION"
				echo "--------------------------------------------------------" >> $site.test_result
				echo "Abort activating prod of $POLICYNAME, as production version has changed while testing staging: old-$OLDPRODVERSION, new-$NEWPRODVERSION" >> $site.test_result
				echo "--------------------------------------------------------" >> $site.test_result
			else
				# Activate this version in production
				rm -rf $site
				echo ""
				echo "$POLICYNAME version $NEWVERSION is ready to be pushed to prod!"
				echo "--------------------------------------------------------" >> $site.test_result
				echo "$POLICYNAME version $NEWVERSION is ready to be pushed to prod!" >> $site.test_result
				echo "--------------------------------------------------------" >> $site.test_result
				#activate_prod
			fi
		else
			echo ""
			echo "Test is failed :("
			cat $site.test_result
		fi
		mail -s "$TESTRETURN $site" $RECEIVER < $site.test_result
		rm -rf $site.test_result
	done
}

check_prod_version()
{
	NEWPRODVERSION=$($MYPYTHON -c "$HEADER; print s.getPolicy('$POLICYID')" | jq -r '.activations[] | "\(.network) \(.policyInfo.status) \(.policyInfo.version)"' | grep prod | awk {'print $3'})
}

activate_prod()
{
	echo ""
	if [ $n -eq 0 ]
	then
		echo ">>>>>>>>>> Activating version $NEWVERSION of $POLICYNAME ($POLICYID) in prod"
		$MYPYTHON -c "$HEADER; print s.activateVersion('$POLICYID','$NEWVERSION', 'prod')" >> .temp1.$POLICYID.prod
		cat .temp1.$POLICYID.prod
		mail -s "`logname` pushed $POLICYNAME version $NEWVERSION to prod" $RECEIVER < .temp1.$POLICYID.prod
	fi
}

# Main function
clear && rm -rf .temp1.*
read_pending_configurations
add_spoof_host
test_redirect
remove_spoof_host

