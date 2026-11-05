CREATE OR REFRESH STREAMING TABLE ${catalog_name}.bronze.plans
AS
SELECT
    *,
    _metadata.file_name AS file_name,
    current_timestamp() AS ingestion_ts
FROM STREAM(
    read_files(
        '/Volumes/${catalog_name}/raw/landing/plans/',
        format => 'csv',
        header => 'true',
        inferColumnTypes => false,
        schemaEvolutionMode => 'addNewColumns',
        rescuedDataColumn => '_rescued_data'
    )
);


CREATE OR REFRESH STREAMING TABLE ${catalog_name}.bronze.claims
AS
SELECT
    *,
    _metadata.file_name AS file_name,
    current_timestamp() AS ingestion_ts
FROM STREAM(
    read_files(
        '/Volumes/${catalog_name}/raw/landing/claims/',
        format => 'json',
        multiLine => 'true',
        inferColumnTypes => true,
        schemaEvolutionMode => 'addNewColumns',
        rescuedDataColumn => '_rescued_data'
    )
);




CREATE OR REFRESH STREAMING TABLE ${catalog_name}.bronze.hospitals
AS
SELECT
    *,
    _metadata.file_name AS file_name,
    current_timestamp() AS ingestion_ts
FROM STREAM(
    read_files(
        '/Volumes/${catalog_name}/raw/landing/hospitals/',
        format => 'csv',
        header => 'true',
        inferColumnTypes => false,
        schemaEvolutionMode => 'addNewColumns',
        rescuedDataColumn => '_rescued_data'
    )
);



CREATE OR REFRESH STREAMING TABLE ${catalog_name}.bronze.hospital_network_history
AS
SELECT
    *,
    _metadata.file_name AS file_name,
    current_timestamp() AS ingestion_ts
FROM STREAM(
    read_files(
        '/Volumes/${catalog_name}/raw/landing/hospital_network_history/',
        format => 'csv',
        header => 'true',
        inferColumnTypes => false,
        schemaEvolutionMode => 'addNewColumns',
        rescuedDataColumn => '_rescued_data'
    )
);



CREATE OR REFRESH STREAMING TABLE ${catalog_name}.bronze.members
AS
SELECT
    *,
    _metadata.file_name AS file_name,
    current_timestamp() AS ingestion_ts
FROM STREAM(
    read_files(
        '/Volumes/${catalog_name}/raw/landing/members/',
        format => 'csv',
        header => 'true',
        inferColumnTypes => false,
        schemaEvolutionMode => 'addNewColumns',
        rescuedDataColumn => '_rescued_data'
    )
);




CREATE OR REFRESH STREAMING TABLE ${catalog_name}.bronze.policy
AS
SELECT
    *,
    _metadata.file_name AS file_name,
    current_timestamp() AS ingestion_ts
FROM STREAM(
    read_files(
        '/Volumes/${catalog_name}/raw/landing/policy_changes_cdc/',
        format => 'json',
        multiLine => 'true',
        inferColumnTypes => true,
        schemaEvolutionMode => 'addNewColumns',
        rescuedDataColumn => '_rescued_data'
    )
);



