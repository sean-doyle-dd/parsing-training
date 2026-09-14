#!/bin/sh
DICT=./words.txt
while [ 1 ]
do
	date=$(date -R);
	random_num=$(( $RANDOM % 100 ));
	other_random_num=$(( $RANDOM % 100 ));
	other_other_random_num=$(( $RANDOM % 15 ));

	if [ $other_random_num -gt 90 ]
	then
		status="ERROR"
	elif [ $other_random_num -gt 80 ]
	then
		status="WARNING"
	elif [ $other_random_num -gt 25 ]
	then
		status="INFO"
	else
		status="DEBUG"
	fi

	something_1=$(shuf -n 1 $DICT)
	something_2=$(shuf -n 1 $DICT)
	uri="https://testsite.com/$something_1?page=$other_random_num#$something_2"

	error_message="$something_2 could not be reached"

	if [ $status == "ERROR" ]
	then
		full_message="[$date] Some text here that isn't JSON. [Message Begins] {\"key\": \"value\", \"another_key\": \"another_value\", \"measure_one\": $random_num, \"status\": \"$status\", \"error_message\": \"$error_message\", \"url\": \"$uri\"} [user$other_other_random_num]"
	else
		full_message="[$date] Some text here that isn't JSON. [Message Begins] {\"key\": \"value\", \"another_key\": \"another_value\", \"measure_one\": $random_num, \"status\": \"$status\", \"url\": \"$uri\"} [user$other_other_random_num]"
	fi

   waitTime=$(shuf -i 1-5 -n 1)
   sleep $waitTime &
   wait $!
   d=`date -Iseconds`
   echo $full_message
done
