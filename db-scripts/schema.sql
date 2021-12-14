CREATE DATABASE testdb;
USE testdb;


DROP TABLE IF EXISTS MOVIE;

CREATE TABLE MOVIE(  
          id int(11) NOT NULL AUTO_INCREMENT,
          name varchar(20),
          year int(11),
          director varchar(20),
          genre varchar(20),
          PRIMARY KEY (id));