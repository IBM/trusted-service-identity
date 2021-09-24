from flask import Flask
from flask_cors import CORS
import MySQLdb
import json
import configparser

app = Flask(__name__)
CORS(app)

config = configparser.ConfigParser()
config.read('./config.ini')

@app.route('/')
def index():
    try:
        db=MySQLdb.connect(host=config["mysql"]["host"],port=int(config["mysql"]["port"]),user=config["mysql"]["user"],
                    passwd=config["mysql"]["passwd"],db=config["mysql"]["db"])
        try:
            cursor = db.cursor()
            output = "<table border=1><thead><tr>"
            # field_names = [i[0] for i in cursor.description]
            # for header in field_names:
                # output += "<th>{}</th>".format(header)
            output += "<th>Movie ID</th>"
            output += "<th>Name</th>"
            output += "<th>Year</th>"
            output += "<th>Director</th>"
            output += "<th>Genre</th>"
            output += "</tr></thead><tbody>"
            cursor.execute("SELECT * FROM MOVIE")
            resultList = cursor.fetchall()
            for row in resultList:
                output += "<tr>"
                for i in range(len(row)):
                    output += "<td>{}</td>".format(row[i])
                output += "</tr>"
            output += "</tbody></table>"
        except Exception as e:
            output =  "Encountered error while retrieving data from database: {}".format(e)
        finally:
            db.close()
        return output
    except MySQLdb.Error as err:
        return "Something went wrong: {}".format(err)
    

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
