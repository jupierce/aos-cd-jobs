import os

import click
import json

import yaml
from atlassian import Jira

if __name__ == '__main__':
    username = os.getenv('JIRA_USERNAME')
    password = os.getenv('JIRA_PASSWORD')
    jira = Jira(url='https://issues.redhat.com', username=username, password=password)

    epics = []
    doc = {'epics': epics}
    offset = 0
    while True:
        r = jira.jql('fixVersion = "OpenShift 4.10" AND ( type = Epic or type = Enhancement )', start=offset)
        count = len(r['issues'])
        if count == 0:
            break

        offset += count
        for i in r['issues']:
            fields = i['fields']
            key = i['key']
            summary = fields['summary'].strip()
            status = fields['status']['name']
            if 'Won\'t' in status or 'Obsolete' in status:
                continue
            epics.append({
                'url': f'https://issues.redhat.com/browse/{key}',
                'summary': summary,
                'status': status
            })

    print(yaml.dump(doc))
