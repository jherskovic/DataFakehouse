CREATE OR REPLACE FUNCTION has_disease(patient_id INTEGER, condition_id VARCHAR(10)) RETURNS BOOLEAN AS $$
DECLARE 
    pid INTEGER;
BEGIN
    SELECT patient INTO pid FROM patients_ground_truth 
        WHERE patient=patient_id AND condition=condition_id;

    RETURN (pid IS NOT NULL);
END;
$$ LANGUAGE plpgsql STABLE RETURNS NULL ON NULL INPUT;
 
CREATE VIEW all_providers_and_conditions AS 
    SELECT p.providerid, c.icd_code FROM
    providers as p, icd_codes as C;

