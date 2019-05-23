CREATE TABLE bad_query (
  word varchar(50),
  number double precision
);

INSERT INTO bad_query
  SELECT table1.word, table2.number
  FROM table1 JOIN table2 ON table1.id = table2.foreign_id;
