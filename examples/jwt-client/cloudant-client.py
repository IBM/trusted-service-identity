# This is just a very simple client to generate HTML file just as proof of concept,
# to demonstrate Trusted Identity use case.
#
# This should not be used in production environment.

import os
import json
# It is helpful to have access to tools
# for formatting date and time values.
from time import gmtime, strftime

from cloudant.client import Cloudant
from cloudant.error import CloudantException
from cloudant.result import Result, ResultByKey

# Functions:
def process_database(databaseName, target):
    myDatabase = client.create_database(databaseName)
    if myDatabase.exists():
        print "'{0}' database exists.\n".format(databaseName)
    result_collection = Result(myDatabase.all_docs, include_docs=True)

    for a in result_collection:
        print "Retrieved full document:\n{0}\n".format(a)
        print "**:\n{0}\n".format(a["doc"]["lastName"])
        doc = a["doc"]
        "{name} and {phone} and {ssn}".format(name="brandon", ssn="123-456-78", phone="8888888")
        line = "\t{lastName} {firstName} \tSSN:{ssn} phone:{phone} rating:{rating}".format(lastName=doc["lastName"], firstName=doc["firstName"],
        ssn=doc["ssn"], phone=doc["phone"], rating=doc["rating"])
        target.write(line)
        #target.write("\t%s %s \tSSN:%s phone:%s rating:%s" % (doc["lastName"], doc["firstName"],
        #doc["ssn"], doc["phone"], doc["rating"]))
        target.write("\n")

claimsfilename = "all-claims"
claims = open(claimsfilename, 'r')

# Change current directory to avoid exposure of control files
try:
    os.mkdir('static')
except OSError:
    # The directory already exists,
    # no need to create it.
    pass
os.chdir('static')

# Begin creating a very simple web page.
filename = "index.html.new"
target = open(filename, 'w')
target.truncate()
target.write("<html><head><title>Trusted Identity Demo</title><meta http-equiv=\"refresh\" content=\"5\" /></head>\n")
target.write("<body><p>Executing access to Cloudant tables...</p><pre>")

# Put a clear indication of the current date and time at the top of the page.
target.write("====\n")
target.write(strftime("%Y-%m-%d %H:%M:%S", gmtime()))
target.write("\n====\n\n")
target.write("</pre><h3>Container Identity</h3><p>\n")
target.write(claims.read())
target.write("</p>\n")

# Start working with the IBM Cloudant service instance.
# IBM Cloudant Legacy authentication
# client = Cloudant("<username>", "<password>", url="<url>")

myurl=os.environ["TARGET_URL"]
username=os.environ["USERNAME"]
API_KEY=os.environ["API_KEY"]

try:
    client = Cloudant(username,API_KEY, url=myurl)
    client.connect()
except:
    print "Error, no matching policy for this identity"
    target.write("<pre>\n====\n\n")
    target.write("\tNO MATCHING POLICIES FOR THIS IDENTITY!!\n\n")
    target.write("</pre></p>")

target.write("<h3>US data results</h3><p><pre>\n")
try:
    databaseName = "ti-users-us"
    process_database(databaseName, target)
except:
    print "Error, no full access to the US DB, trying limited access..."
    try:
        databaseName = "ti-users-us-limit"
        process_database(databaseName, target)
    except:
        print "Error, no access to the DB"
        target.write("\tNO DATABASE ACCESS!!\n")
        target.write("\n")

# Put another clear indication of the current date and time at the bottom of the page.
target.write("\n====\n")
target.write("</pre></p><h3>EU data results</h3><p><pre>")

try:
    databaseName = "ti-users-eu"
    process_database(databaseName, target)
except:
    print "Error, no full access to the EU DB, trying limited access..."
    try:
        databaseName = "ti-users-eu-limit"
        process_database(databaseName, target)
    except:
        print "Error, no access to the DB"
        target.write("\tNO DATABASE ACCESS!!\n")
        target.write("\n")

target.write("\n====\n")
target.write(strftime("%Y-%m-%d %H:%M:%S", gmtime()))
target.write("\n====\n")

# Finish creating the web page.
target.write("</pre></body></html>")
target.close()
client.disconnect()
