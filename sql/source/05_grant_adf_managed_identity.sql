/* =====================================================================
   ShopStream | Day 2 | Let Data Factory's managed identity into the DB
   05 - run while signed in with MICROSOFT ENTRA authentication
        (Query editor -> "Continue as <you>"), NOT the SQL login:
        only an Entra principal can create users FROM EXTERNAL PROVIDER.

   The user name is the Data Factory's name. No password exists anywhere:
   ADF gets a token from Entra ID for its own identity.
   Least privilege: read the source tables, run the etl procedures.
   ===================================================================== */

CREATE USER [adf-shopstream-cr] FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [adf-shopstream-cr];   -- SELECT on olist.* and etl.*
GRANT EXECUTE ON SCHEMA::etl TO [adf-shopstream-cr];      -- run the logging procedures

-- Check
SELECT dp.name, dp.type_desc, r.name AS role_name
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members rm ON rm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
WHERE dp.name = 'adf-shopstream-cr';
