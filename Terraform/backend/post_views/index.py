import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

LOGLEVEL = os.environ.get('LOGLEVEL', 'INFO').upper()
logging_format = '[%(levelname)s] %(filename)s:%(lineno)d %(message)s'
logging.basicConfig(
    level=LOGLEVEL,
    format=logging_format,
)

logging.getLogger('botocore').setLevel(logging.ERROR)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('crc-counter')

def lambda_handler(event, context):

    """extracts the CloudFront response object from the event parameter 
    and updates its status and statusDescription fields to indicate a 
    successful response. The updated response object is then 
    returned by the function."""

    cf_response = event['Records'][0]['cf']['response']
    logging.info(cf_response)

    """Update the viewer count DynamoDB table"""

    try:
        response = table.get_item(Key={"CounterID": '1'})
        views = response['Item']['views']
        views += 1
        logging.info(f'Current total view count is {views}.')
        response = table.put_item(Item={
            'CounterID': '1',
            'views': views
        })
        logging.info('Successfully updated the DynamoDB table')
    except ClientError as e:
        logging.error(e)
    except KeyError as e:
        logging.error(f"KeyError: {e}")

    # Update the response status and status description
    cf_response['status'] = 200
    cf_response['statusDescription'] = 'OK'

    return cf_response



