from flask import Flask, request, redirect
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
                output += "<td><a href='/delete/"+str(row[0])+"'>Delete</a></td>"
                output += "</tr>"
            output += "</tbody></table>"

            output += "<hr>";
            output += """<form action='/addmovie' method='POST'>
                    <table><tbody>
                        <tr>
                            <td><label for='name'>Name</label></td>
                            <td><input id='name' type='text' placeholder='name' name='name'></td>
                        </tr>
                        <tr>
                            <td><label for='year'>Year</label></td>
                            <td><input id='year' type='number' placeholder='year' name='year'></td>
                        </tr>
                        <tr>
                            <td><label for='director'>Director</label></td>
                            <td><input id='director' type='text' placeholder='director' name='director'></td>
                        </tr>
                        <tr>
                            <td><label for='genre'>Genre</label></td>
                            <td><input id='genre' type='text' placeholder='genre' name='genre'></td>
                        </tr>
                        <tr><td colspan=2><button type='submit'>Add</button></td></tr>
                    </tbody></table>
                </form>""";
            output += "<hr>";
        except Exception as e:
            output =  "Encountered error while retrieving data from database: {}".format(e)
        finally:
            db.close()
        return output
    except MySQLdb.Error as err:
        return "Something went wrong: {}".format(err)

@app.route('/delete/<id>', methods = ['GET'])
def deletemovie(id):
    try:
        db=MySQLdb.connect(host=config["mysql"]["host"],port=int(config["mysql"]["port"]),user=config["mysql"]["user"],
                    passwd=config["mysql"]["passwd"],db=config["mysql"]["db"])
        try:
            mycursor = db.cursor()

            sql = "DELETE FROM MOVIE WHERE id = "+id
            mycursor.execute(sql)
            db.commit()
            print(mycursor.rowcount, "record(s) deleted")
        except Exception as e:
            return "Encountered error while retrieving data from database: {}".format(e)
        finally:
            db.close()
        return redirect("/")
    except MySQLdb.Error as err:
        return "Something went wrong: {}".format(err)

@app.route('/addmovie', methods = ['POST'])
def addmovie():
    try:
        data = request.form
        # print(data)
        db=MySQLdb.connect(host=config["mysql"]["host"],port=int(config["mysql"]["port"]),user=config["mysql"]["user"],
                    passwd=config["mysql"]["passwd"],db=config["mysql"]["db"])
        try:
            mycursor = db.cursor()

            sql = "INSERT INTO MOVIE (`name`,`year`,`director`,`genre`) VALUES (%s, %s, %s, %s)"
            val = [(v) for k, v in data.items()]
            print (val)
            mycursor.execute(sql, val)

            db.commit()

            print(mycursor.rowcount, "record inserted.")
        except Exception as e:
            return "Encountered error while retrieving data from database: {}".format(e)
        finally:
            db.close()
        return redirect("/")
    except MySQLdb.Error as err:
        return "Something went wrong: {}".format(err)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
