const express = require('express');
const mysql = require('mysql');
// const mysql2 = require('mysql2');
const configfile = require("./config.json");
const app = express();
const PORT = 8080;
const HOST = '0.0.0.0';

let connection;

app.get('/', (req, res) => {
    if (!connection){
        connection = mysql.createConnection(configfile);
        connection.connect();
    }
    connection.query('SELECT * FROM MOVIE', function (error, results, fields) {
        if (error) throw error;

        var output = "<table border=1>";
        output += "<thead><tr>"
        if (fields && fields.length){
            output += fields.reduce((acc,field)=> {return acc+`<th>${field.name}</th>`;}, "");
        } else {
            output += "<th>Movie ID</th>";
            output += "<th>Name</th>";
            output += "<th>Year</th>";
            output += "<th>Director</th>";
            output += "<th>Genre</th>";
        }
        output += "</tr></thead><tbody>"
        if (results && results.length){
            output += results.reduce((acc,result)=> {
                return acc+"<tr>"+
                    fields.reduce((acc2, field)=> {
                        return acc2+`<td>${result[field.name]}</td>`;
                    }, "")+"</tr>";
            }, "");
        }
        output += "</tbody></table>";

        res.send(output);
    });
})

app.listen(PORT, HOST, () => {
    console.log(`Running on http://${HOST}:${PORT}`);
})