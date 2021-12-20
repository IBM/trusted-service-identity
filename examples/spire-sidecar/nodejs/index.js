const express = require('express');
const bodyParser = require('body-parser')
const mysql = require('mysql');
// const mysql2 = require('mysql2');
const configfile = require("./config.json");
const app = express();
const PORT = 8080;
const HOST = '0.0.0.0';

let connection;

app.use( bodyParser.json() );       // to support JSON-encoded bodies
app.use(bodyParser.urlencoded({     // to support URL-encoded bodies
  extended: true
})); 

app.get('/', (req, res) => {
    if (!connection){
        connection = mysql.createConnection(configfile);
        connection.connect();
    }
    connection.query('SELECT * FROM MOVIE', function (error, results, fields) {
        if (error) {
            res.send(error);
            return;
            // throw error;
        }

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
            output += "<th>-</th>";
        }
        output += "</tr></thead><tbody>"
        if (results && results.length){
            output += results.reduce((acc,result)=> {
                return acc+"<tr>"+
                    fields.reduce((acc2, field)=> {
                        return acc2+`<td>${result[field.name]}</td>`;
                    }, "")+ "<td><a href='/delete/"+result['id']+"'>Delete</a></td>"  +"</tr>";
            }, "");
        }
        output += "</tbody></table>";

        output += "<hr>";
        output += 
            
            '<form action="/addmovie" method="POST">'+
                '<table><tbody>'+
                    '<tr>'+
                        '<td><label for="name">Name</label></td>'+
                        '<td><input id="name" type="text" placeholder="name" name="name"></td>'+
                    '</tr>'+
                    '<tr>'+
                        '<td><label for="year">Year</label></td>'+
                        '<td><input id="year" type="number" placeholder="year" name="year"></td>'+
                    '</tr>'+
                    '<tr>'+
                        '<td><label for="director">Director</label></td>'+
                        '<td><input id="director" type="text" placeholder="director" name="director"></td>'+
                    '</tr>'+
                    '<tr>'+
                        '<td><label for="genre">Genre</label></td>'+
                        '<td><input id="genre" type="text" placeholder="genre" name="genre"></td>'+
                    '</tr>'+
                    '<tr><td colspan=2><button type="submit">Add</button></td></tr>'+
                '</tbody></table>'+
            '</form>';
            
        output += "<hr>";

        res.send(output);
    });
})

app.post('/addmovie', (req, res) => {
    if (!connection){
        connection = mysql.createConnection(configfile);
        connection.connect();
    }
    connection.query('INSERT INTO MOVIE SET ?', req.body, function (error, results, fields) {
        if (error) {
            throw error;
        }
        if (results.insertId){
            return res.redirect('/');
        }
    });
});

app.get('/delete/:id', (req, res) => {
    if (!connection){
        connection = mysql.createConnection(configfile);
        connection.connect();
    }
    connection.query('DELETE FROM MOVIE WHERE id = '+req.params.id, function (error, results, fields) {
        if (error) {
            throw error;
        }
        if (results.affectedRows){
            return res.redirect('/');
        }
    });
});

app.listen(PORT, HOST, () => {
    console.log(`Running on http://${HOST}:${PORT}`);
})