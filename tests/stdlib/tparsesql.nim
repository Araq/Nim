discard """
  targets: "c js"
"""
import parsesql
import std/assertions
doAssert treeRepr(parseSql("INSERT INTO STATS VALUES (10, 5.5); ")
) == """

nkStmtList
  nkInsert
    nkIdent STATS
    nkNone
    nkValueList
      nkIntegerLit 10
      nkNumericLit 5.5"""

doAssert $parseSQL("SELECT foo FROM table;") == "select foo from table;"
doAssert $parseSQL("""
SELECT
  CustomerName,
  ContactName,
  Address,
  City,
  PostalCode,
  Country,
  CustomerName,
  ContactName,
  Address,
  City,
  PostalCode,
  Country
FROM table;""") == "select CustomerName, ContactName, Address, City, PostalCode, Country, CustomerName, ContactName, Address, City, PostalCode, Country from table;"

doAssert $parseSQL("SELECT foo FROM table limit 10") == "select foo from table limit 10;"
doAssert $parseSQL("SELECT foo, bar, baz FROM table limit 10") == "select foo, bar, baz from table limit 10;"
doAssert $parseSQL("SELECT foo AS bar FROM table") == "select foo as bar from table;"
doAssert $parseSQL("SELECT foo AS foo_prime, bar AS bar_prime, baz AS baz_prime FROM table") == "select foo as foo_prime, bar as bar_prime, baz as baz_prime from table;"
doAssert $parseSQL("SELECT * FROM table") == "select * from table;"
doAssert $parseSQL("SELECT count(*) FROM table") == "select count(*) from table;"
doAssert $parseSQL("SELECT count(*) as 'Total' FROM table") == "select count(*) as 'Total' from table;"
doAssert $parseSQL("SELECT count(*) as 'Total', sum(a) as 'Aggr' FROM table") == "select count(*) as 'Total', sum(a) as 'Aggr' from table;"

doAssert $parseSQL("""
SELECT * FROM table
WHERE a = b and c = d
""") == "select * from table where a = b and c = d;"

doAssert $parseSQL("""
SELECT * FROM table
WHERE not b
""") == "select * from table where not b;"

doAssert $parseSQL("""
SELECT
  *
FROM
  table
WHERE
  a and not b
""") == "select * from table where a and not b;"

doAssert $parseSQL("""
SELECT * FROM table
ORDER BY 1
""") == "select * from table order by 1;"

doAssert $parseSQL("""
SELECT * FROM table
GROUP BY 1
ORDER BY 1
""") == "select * from table group by 1 order by 1;"

doAssert $parseSQL("""
SELECT * FROM table
ORDER BY 1
LIMIT 100
""") == "select * from table order by 1 limit 100;"

doAssert $parseSQL("""
SELECT * FROM table
WHERE a = b and c = d or n is null and not b + 1 = 3
""") == "select * from table where a = b and c = d or n is null and not b + 1 = 3;"

doAssert $parseSQL("""
SELECT * FROM table
WHERE (a = b and c = d) or (n is null and not b + 1 = 3)
""") == "select * from table where(a = b and c = d) or (n is null and not b + 1 = 3);"

doAssert $parseSQL("""
SELECT * FROM table
HAVING a = b and c = d
""") == "select * from table having a = b and c = d;"

doAssert $parseSQL("""
SELECT a, b FROM table
GROUP BY a
""") == "select a, b from table group by a;"

doAssert $parseSQL("""
SELECT a, b FROM table
GROUP BY 1, 2
""") == "select a, b from table group by 1, 2;"

doAssert $parseSQL("SELECT t.a FROM t as t") == "select t.a from t as t;"

doAssert $parseSQL("""
SELECT a, b FROM (
  SELECT * FROM t
)
""") == "select a, b from(select * from t);"

doAssert $parseSQL("""
SELECT a, b FROM (
  SELECT * FROM t
) as foo
""") == "select a, b from(select * from t) as foo;"

doAssert $parseSQL("""
SELECT a, b FROM (
  SELECT * FROM (
    SELECT * FROM (
      SELECT * FROM (
        SELECT * FROM innerTable as inner1
      ) as inner2
    ) as inner3
  ) as inner4
) as inner5
""") == "select a, b from(select * from(select * from(select * from(select * from innerTable as inner1) as inner2) as inner3) as inner4) as inner5;"

doAssert $parseSQL("""
SELECT a, b FROM
  (SELECT * FROM a),
  (SELECT * FROM b),
  (SELECT * FROM c)
""") == "select a, b from(select * from a),(select * from b),(select * from c);"

doAssert $parseSQL("""
SELECT * FROM Products
WHERE Price BETWEEN 10 AND 20;
""") == "select * from Products where Price between 10 and 20;"

doAssert $parseSQL("""
SELECT id FROM a
JOIN b
ON a.id == b.id
""") == "select id from a join b on a.id == b.id;"

doAssert $parseSQL("""
SELECT id FROM a
JOIN (SELECT id from c) as b
ON a.id == b.id
""") == "select id from a join(select id from c) as b on a.id == b.id;"

doAssert $parseSQL("""
SELECT id FROM a
INNER JOIN b
ON a.id == b.id
""") == "select id from a inner join b on a.id == b.id;"

doAssert $parseSQL("""
SELECT id FROM a
OUTER JOIN b
ON a.id == b.id
""") == "select id from a outer join b on a.id == b.id;"

doAssert $parseSQL("""
SELECT id FROM a
CROSS JOIN b
ON a.id == b.id
""") == "select id from a cross join b on a.id == b.id;"

doAssert $parseSQL("""
CREATE TYPE happiness AS ENUM ('happy', 'very happy', 'ecstatic');
CREATE TABLE holidays (
  num_weeks int,
  happiness happiness
);
CREATE INDEX table1_attr1 ON table1(attr1);
SELECT * FROM myTab WHERE col1 = 'happy';
""") == "create type happiness as enum ('happy' , 'very happy' , 'ecstatic' ); create table holidays(num_weeks  int , happiness  happiness );; create index table1_attr1 on table1(attr1 );; select * from myTab where col1 = 'happy';"

doAssert $parseSQL("""
INSERT INTO Customers (CustomerName, ContactName, Address, City, PostalCode, Country)
VALUES ('Cardinal', 'Tom B. Erichsen', 'Skagen 21', 'Stavanger', '4006', 'Norway');
""") == "insert into Customers (CustomerName , ContactName , Address , City , PostalCode , Country ) values ('Cardinal' , 'Tom B. Erichsen' , 'Skagen 21' , 'Stavanger' , '4006' , 'Norway' );"

doAssert $parseSQL("""
INSERT INTO TableName DEFAULT VALUES
""") == "insert into TableName default values;"

doAssert $parseSQL("""
UPDATE Customers
SET ContactName = 'Alfred Schmidt', City= 'Frankfurt'
WHERE CustomerID = 1;
""") == "update Customers set ContactName  = 'Alfred Schmidt' , City  = 'Frankfurt' where CustomerID = 1;"

doAssert treeRepr(parseSql("""UPDATE Customers
                              SET ContactName = 'Alice', City= 'Frankfurt';""")
) == """

nkStmtList
  nkUpdate
    nkIdent Customers
    nkAsgn
      nkIdent ContactName
      nkStringLit Alice
    nkAsgn
      nkIdent City
      nkStringLit Frankfurt
    nkNone"""

doAssert $parseSQL("DELETE FROM table_name;") == "delete from table_name;"

doAssert treeRepr(parseSQL("DELETE FROM table_name;")
) == """

nkStmtList
  nkDelete
    nkIdent table_name
    nkNone"""

doAssert $parseSQL("DELETE * FROM table_name;") == "delete from table_name;"

doAssert $parseSQL("""
--Select all:
SELECT * FROM Customers;
""") == "select * from Customers;"

doAssert $parseSQL("""
SELECT * FROM Customers WHERE (CustomerName LIKE 'L%'
OR CustomerName LIKE 'R%' /*OR CustomerName LIKE 'S%'
OR CustomerName LIKE 'T%'*/ OR CustomerName LIKE 'W%')
AND Country='USA'
ORDER BY CustomerName;
""") == "select * from Customers where(CustomerName like 'L%' or CustomerName like 'R%' or CustomerName like 'W%') and Country = 'USA' order by CustomerName;"

# parse quoted keywords as identifires
doAssert $parseSQL("""
SELECT `SELECT`, `FROM` as `GROUP` FROM `WHERE`;
""") == """select "SELECT", "FROM" as "GROUP" from "WHERE";"""
doAssert $parseSQL("""
SELECT "SELECT", "FROM" as "GROUP" FROM "WHERE";
""") == """select "SELECT", "FROM" as "GROUP" from "WHERE";"""
