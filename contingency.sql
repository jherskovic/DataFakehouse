
-- The results of the following call are cached automagically by Postgres
CREATE OR REPLACE FUNCTION has_disease(patient_id INTEGER, condition_id VARCHAR(10)) RETURNS BOOLEAN AS $$
DECLARE 
    pid INTEGER;
BEGIN
    SELECT patient INTO pid FROM patients_ground_truth 
    WHERE patient=patient_id AND icd_code=condition_id;

    RETURN (pid IS NOT NULL);
END;
$$ LANGUAGE plpgsql STABLE RETURNS NULL ON NULL INPUT;
 
CREATE TEMP VIEW all_labs_and_conditions AS 
    SELECT l.lab_testid, c.code 
    FROM lab_tests AS l, icd_codes AS c;

-- This view shows whether each test is normal (i.e. negative) or abnormal.
-- Bonus: it includes the patient's id.
CREATE VIEW lab_results AS
    SELECT l.lab_testid, v.visitid AS visit, v.patient,
           (t.value BETWEEN l.normal_min and l.normal_max) AS is_normal
    FROM lab_tests AS l 
    INNER JOIN labs AS t ON t.lab_test=l.lab_testid
    INNER JOIN visits AS v ON v.visitid=t.visit;
      
-- Counts how many times a lab was performed on a patients with each condition
CREATE TEMP VIEW lab_condition_encounters AS
    SELECT l.lab_testid, l.code, COUNT(r.patient) AS encounters
    FROM all_labs_and_conditions l 
    INNER JOIN lab_results r ON r.lab_testid=l.lab_testid
    WHERE has_disease(r.patient, l.code)
    GROUP BY l.lab_testid, l.code;

-- Counts how many times a lab was performed on a patients without
-- each condition
CREATE TEMP VIEW lab_other_condition_encounters AS
    SELECT l.lab_testid, l.code, COUNT(r.patient) AS times_performed
    FROM all_labs_and_conditions l 
    INNER JOIN lab_results r ON r.lab_testid=l.lab_testid
    WHERE has_disease(r.patient, l.code)=False
    GROUP BY l.lab_testid, l.code;

-- Counts how many times patients with a condition had an abnormal lab result
-- (i.e. a true positive) and computes how many had a normal lab result
-- (i.e. a false negative)
CREATE TEMP VIEW tp_fn_labs_for_conditions AS
    SELECT l.lab_testid, l.code, l.encounters, 
           count(r.patient) AS true_positives,
           l.encounters-count(r.patient) as false_negatives
    FROM lab_condition_encounters l 
    LEFT OUTER JOIN (SELECT * FROM lab_results WHERE is_normal=False) AS r 
        ON r.lab_testid=l.lab_testid
        AND has_disease(r.patient, l.code)
    GROUP BY l.lab_testid, l.code, l.encounters;

-- Counts how many times patients without a condition had a normal lab result
-- (i.e. a true negative) and computes how many times  
CREATE TEMP VIEW tn_fp_labs_for_conditions AS
    SELECT l.lab_testid, l.code, l.times_performed, 
           count(r.patient) AS true_negatives,
           l.times_performed - count(r.patient) as false_positives
    FROM lab_other_condition_encounters l 
    LEFT OUTER JOIN (SELECT * FROM lab_results WHERE is_normal=True) AS r 
        ON r.lab_testid=l.lab_testid
        AND has_disease(r.patient, l.code)=False
    GROUP BY l.lab_testid, l.code, l.times_performed;

-- Create the labs contingency table
SELECT l.lab_testid AS lab_test, l.code as icd_code,
       tp.true_positives, 
       tp.false_negatives, 
       tn.true_negatives, 
       tn.false_positives
INTO contingency_table_labs
FROM all_labs_and_conditions AS l
INNER JOIN tp_fn_labs_for_conditions tp 
    ON tp.lab_testid=l.lab_testid
    AND tp.code=l.code
INNER JOIN tn_fp_labs_for_conditions as tn
    ON tn.lab_testid=l.lab_testid
    AND tn.code=l.code;

CREATE INDEX idx_lab_contingency ON contingency_table_labs (lab_test, icd_code);

CREATE TEMP VIEW all_providers_and_conditions AS 
    SELECT p.providerid, c.code 
    FROM providers AS p, icd_codes AS c;

CREATE TEMP VIEW provider_exam_results AS
    SELECT p.problemid, v.provider, v.patient, p.icd_code,
           has_disease(v.patient, p.icd_code) as true_positive
    FROM problems AS p 
    INNER JOIN visits AS v ON p.visit=v.visitid;

CREATE TEMP VIEW times_provider_encounters_condition AS
    SELECT p.providerid, p.code, COUNT(v.patient) as encounters
    FROM all_providers_and_conditions AS p
    INNER JOIN visits AS V
        ON v.provider=p.providerid
    WHERE has_disease(v.patient, p.code)=True
    GROUP BY p.providerid, p.code;

CREATE TEMP VIEW times_provider_does_not_encounter_condition AS
    SELECT p.providerid, p.code, COUNT(v.patient) as encounters
    FROM all_providers_and_conditions AS p
    INNER JOIN visits AS V
        ON v.provider=p.providerid
    WHERE has_disease(v.patient, p.code)=False
    GROUP BY p.providerid, p.code;

CREATE TEMP VIEW tp_fn_providers_for_conditions AS
    SELECT p.providerid, p.code, 
           count(t.problemid) AS true_positives,
           p.encounters-COUNT(t.problemid) AS false_negatives
    FROM times_provider_encounters_condition AS p
    LEFT OUTER JOIN (SELECT * FROM provider_exam_results 
                     WHERE true_positive=True) AS t
        ON p.providerid=t.provider
        AND p.code=t.icd_code
    GROUP BY p.providerid, p.code, p.encounters;

CREATE TEMP VIEW tn_fp_providers_for_conditions AS
    SELECT p.providerid, p.code, 
           count(t.problemid) AS false_positives,
           p.encounters-COUNT(t.problemid) AS true_negatives
    FROM times_provider_does_not_encounter_condition AS p
    LEFT OUTER JOIN (SELECT * FROM provider_exam_results 
                     WHERE true_positive=False)
                     AS t
        ON p.providerid=t.provider
        AND p.code=t.icd_code
    GROUP BY p.providerid, p.code, p.encounters;

SELECT p.providerid AS provider, p.code AS icd_code,
       tp.true_positives, tp.false_negatives,
       tn.true_negatives, tn.false_positives
INTO contingency_table_providers
FROM all_providers_and_conditions AS p
    INNER JOIN tp_fn_providers_for_conditions AS tp
        ON p.providerid=tp.providerid
        AND p.code=tp.code
    INNER JOIN tn_fp_providers_for_conditions AS tn
        ON p.providerid=tn.providerid
        AND p.code=tn.code;

CREATE INDEX idx_providers_contingency 
ON contingency_table_providers (provider, icd_code);

CREATE VIEW labs_sensitivity_specificity AS
    SELECT lab_test, icd_code,
           true_positives::double precision/(true_positives+false_negatives)::double precision AS sensitivity,
           true_negatives::double precision/(true_negatives+false_positives)::double precision AS specificity
    FROM contingency_table_labs;
    
CREATE VIEW providers_sensitivity_specificity AS
    SELECT provider, icd_code,
           true_positives::double precision/(true_positives+false_negatives)::double precision AS sensitivity,
           true_negatives::double precision/(true_negatives+false_positives)::double precision AS specificity
    FROM contingency_table_providers;
        
CREATE TEMP VIEW visits_with_condition_billed_as_such AS
    SELECT p.icd_code, COUNT(v.visitid) as visit_count
    FROM visits AS v
    INNER JOIN patients_ground_truth AS p
        ON p.patient=v.patient
    INNER JOIN billing AS b
        ON b.visit=v.visitid
        AND b.icd_code=p.icd_code
    GROUP BY p.icd_code;

CREATE TEMP VIEW visits_with_condition_not_billed_as_such AS
    SELECT p.icd_code, COUNT(v.visitid) as visit_count
    FROM visits AS v
    INNER JOIN patients_ground_truth AS p
        ON p.patient=v.patient
    WHERE p.icd_code NOT IN (SELECT icd_code 
                             FROM billing 
                             WHERE visit=v.visitid)
    GROUP BY p.icd_code;

CREATE TEMP VIEW conditions_a_patient_does_not_have AS
    SELECT DISTINCT p.patient, c.code
    FROM patients_ground_truth AS p, icd_codes AS c
    WHERE has_disease(p.patient, c.code)=False;

CREATE TEMP VIEW visits_without_condition_billed_for_it_anyway AS
    SELECT c.code as icd_code, COUNT(v.visitid) AS visit_count
    FROM conditions_a_patient_does_not_have AS c 
    INNER JOIN visits AS v
        ON v.patient=c.patient
    WHERE c.code IN (SELECT icd_code 
                     FROM billing
                     WHERE visit=v.visitid)
    GROUP BY c.code;
    
CREATE TEMP VIEW visits_without_condition_not_billed_for_it AS
    SELECT c.code as icd_code, COUNT(v.visitid) AS visit_count
    FROM conditions_a_patient_does_not_have AS c 
    INNER JOIN visits AS v
        ON v.patient=c.patient
    WHERE c.code NOT IN (SELECT icd_code 
                         FROM billing
                         WHERE visit=v.visitid)
    GROUP BY c.code;

CREATE TEMP VIEW billing_contingency_view AS 
    SELECT c.code AS icd_code, 
           COALESCE(tp.visit_count, 0) AS true_positives,
           COALESCE(fn.visit_count, 0) AS false_negatives,
           COALESCE(fp.visit_count, 0) AS false_positives,
           COALESCE(tn.visit_count, 0) AS true_negatives
    FROM icd_codes AS c
    LEFT OUTER JOIN visits_with_condition_billed_as_such AS tp
        ON tp.icd_code=c.code
    LEFT OUTER JOIN visits_with_condition_not_billed_as_such AS fn
        ON fn.icd_code=c.code
    LEFT OUTER JOIN visits_without_condition_billed_for_it_anyway AS fp
        ON fp.icd_code=c.code
    LEFT OUTER JOIN visits_without_condition_not_billed_for_it AS tn
        ON tn.icd_code=c.code
    ORDER BY c.code;
    
SELECT * 
INTO contingency_table_billing
FROM billing_contingency_view;

CREATE INDEX idx_contingency_billing ON contingency_table_billing (icd_code);

CREATE VIEW billing_sensitivity_specificity AS
SELECT icd_code, 
       true_positives::double precision/(true_positives+false_negatives)::double precision AS sensitivity,
       true_negatives::double precision/(true_negatives+false_positives)::double precision AS specificity
   FROM contingency_table_billing;
