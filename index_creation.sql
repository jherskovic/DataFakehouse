CREATE UNIQUE INDEX idx_ground_truth_patients ON patients_ground_truth (patient, icd_code);
CREATE INDEX idx_ground_truth_conditions ON patients_ground_truth (icd_code);

CREATE INDEX idx_problems_visits ON problems (visit);
CREATE INDEX idx_problems_conditions ON problems (icd_code);

CREATE INDEX idx_labs_visits ON labs (visit);
CREATE INDEX idx_labs_lab ON labs (lab_test);
