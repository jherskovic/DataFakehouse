CREATE LANGUAGE plpgsql;

CREATE TABLE races (
    raceid SERIAL NOT NULL PRIMARY KEY,
    name VARCHAR(50)
);
CREATE INDEX idx_race ON races(name);

CREATE TABLE patients (
    patientid SERIAL NOT NULL PRIMARY KEY,
    age INTEGER NOT NULL,
    race INTEGER NULL REFERENCES races
);

CREATE TABLE providers (
    providerid SERIAL NOT NULL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    title VARCHAR(20) NOT NULL
);
CREATE INDEX idx_providers ON providers(name);

CREATE TABLE visits (
    visitid SERIAL NOT NULL PRIMARY KEY,
    provider INTEGER NOT NULL REFERENCES providers,
    patient INTEGER NOT NULL REFERENCES patients,
    visit_date TIMESTAMP NOT NULL DEFAULT current_timestamp
);

CREATE TABLE icd_codes (
    code VARCHAR(10) NOT NULL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    prevalence NUMERIC NOT NULL
);

CREATE TABLE patients_ground_truth (
    patient INTEGER NOT NULL REFERENCES patients,
    icd_code VARCHAR(10) NOT NULL
);

CREATE TABLE problems (
    problemid SERIAL NOT NULL PRIMARY KEY,
    visit INTEGER NOT NULL REFERENCES visits,
    icd_code VARCHAR(10) NOT NULL REFERENCES icd_codes
);

CREATE TABLE units (
    unit VARCHAR(10) NOT NULL PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

--normal_min and normal_max describe the normal range of the test
CREATE TABLE lab_tests (
    lab_testid SERIAL NOT NULL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    unit VARCHAR(10) NOT NULL REFERENCES units,
    normal_min NUMERIC NOT NULL,
    normal_max NUMERIC NOT NULL
);

-- The NUMERIC column in PostgreSQL allows storing any arbitrary-precision number
-- and, without specifying a format (i.e. NUMERIC(16,0)) it doesn't coerce it.
CREATE TABLE labs (
    labid SERIAL NOT NULL PRIMARY KEY,
    visit INTEGER NOT NULL REFERENCES visits,
    lab_test INTEGER NOT NULL REFERENCES lab_tests,
    value NUMERIC NOT NULL 
);

--Populate some of the master tables
--Providers shamelessly cribbed from TV series
INSERT INTO providers (name, title) VALUES
    ('Gregory House',   'MD'),
    ('Perry Cox',       'MD'),
    ('John Dorian',     'MD'),
    ('Carla Espinoza',  'RN'),
    ('Chris Turk',      'MD'),
    ('Elliot Reid',     'MD'),
    ('Abby Lockhart',   'MD'),
    ('Malik McGrath',   'RN'),
    ('Chuck Martin',    'RN'),
    ('Lily Jarvik',     'RN');

--Bagelitis doesn't sound like such a horrible disease
--And I definitely suffer from hypocaffeinemia
INSERT INTO icd_codes (code, name, prevalence) VALUES 
    ('012', 'Hairitis',             0.3),
    ('345', 'Sarcasmosis',          0.01),
    ('678', 'Bagelitis',            0.2),
    ('9AB', 'Annoyingism',          0.3),
    ('CDE', 'Hyperpressure',        0.1),
    ('999', 'Diabitter mellitus',   0.15),
    ('XYZ', 'Wristache',            0.45),
    ('987', 'Hypocaffeinemia',      0.6);

--Rods to the hogshead is a quintessential American measurement according to Grampa Simpson
INSERT INTO units (unit, name) VALUES 
    ('g/dL',    'Grams per deciliter'),
    ('mg/ml',   'Milligrams per milliliter'),
    ('g/m2',    'Grams per square meter'),
    ('mg/g',    'Milligrams per gram'),
    ('r/hh',    'Rods to the hogshead'),
    ('u/ml',    'Units per milliliter'),
    ('%',       'Percentage'),
    ('gal',     'Gallons'),
    ('C',       'Degrees celsius'),
    ('mmHg',    'Mercury millimiters');

--...and it was used to measure fuel efficiency.
INSERT INTO lab_tests (name, unit, normal_min, normal_max) VALUES 
    ('Blood glucose',               'mg/ml',    50,   140),
    ('Brain tissue glucose',        'mg/g',     20,    90),
    ('Sarcasmin in exhaled gas',    'g/m2',     10,   100),
    ('Hematocrit',                  '%',        35,    45),
    ('White cell count in fingers', 'u/ml',   9999, 15000),
    ('Blood Hemogrossin',           'mg/ml',    50,    99),
    ('Fuel efficiency',             'r/hh',      7,    20),
    ('Fuel capacity',               'gal',       5,    20),
    ('Eyeball temperature',         'C',        32,    35),
    ('Diabatic pressure',           'mmHg',     40,    90),
    ('Systematic pressure',         'mmHg',    100,   140),
    ('IQ',                          '%',        80,   120),
    ('Other lab test 1',            'mg/ml',    10,    20),
    ('Other lab test 2',            'mg/ml',    20,    40),
    ('Other lab test 3',            'mg/ml',    30,    35),
    ('Other lab test 4',            'mg/ml',    40,    90),
    ('Other lab test 5',            'mg/ml',    50,    55),
    ('Other lab test 6',            'mg/ml',    60,   100),
    ('Other lab test 7',            'mg/ml',    70,   200),
    ('Other lab test 8',            'mg/ml',    80,    90),
    ('Other lab test 9',            'mg/ml',    90,    95),
    ('Other lab test 10',           'mg/ml',     0,     5),
    ('Other lab test 11',           'mg/ml',     1,     7),
    ('Other lab test 12',           'mg/ml',     2,    20),
    ('Other lab test 13',           'mg/ml',     3,    20),
    ('Other lab test 14',           'mg/ml',     4,    20),
    ('Other lab test 15',           'mg/ml',     5,    20),
    ('Other lab test 16',           'mg/ml',     6,    77),
    ('Other lab test 17',           'mg/ml',     7,    32),
    ('Other lab test 18',           'mg/ml',     8,    20),
    ('Other lab test 19',           'mg/ml',     9,    20),
    ('Other lab test 20',           'mg/ml',    10,    20)
    ;
    
--Fake races offend no one. Hopefully.
INSERT INTO races (name) VALUES 
    ('Blue-American'),
    ('Magenta-American'),
    ('Green-American'),
    ('Puce-American'),
    ('Polka dot-American');
    
--Since fully normalized DBs are a pain without a user interface, create some stored procedures
--to make using them somewhat sane. These return the ID of the record just created.
-- These are used by the "populate" python script.
CREATE FUNCTION NewPatient(age_param INTEGER, race_param VARCHAR(50)) RETURNS INTEGER AS $$
DECLARE 
    newid INTEGER;
    known_raceid INTEGER;
BEGIN
    SELECT raceid INTO known_raceid FROM races WHERE name=race_param;
    
    INSERT INTO patients (age, race) VALUES (age_param, known_raceid);
    SELECT currval('patients_patientid_seq') INTO newid;
    
    RETURN newid;
END;
$$ LANGUAGE plpgsql;

--The next function expects a number of days before today
CREATE FUNCTION NewVisit(provider_name VARCHAR(100), patient_id INTEGER, visit_age INTEGER) RETURNS INTEGER AS $$
DECLARE
    newid INTEGER;
    known_provider_id INTEGER;
    computed_visit_date TIMESTAMP;
BEGIN
    SELECT providerid INTO known_provider_id FROM providers WHERE name=provider_name;
    
    computed_visit_date:=now()-(visit_age::TEXT || ' days')::INTERVAL;
    
    INSERT INTO visits (provider, patient, visit_date) 
        VALUES (known_provider_id, patient_id, computed_visit_date);
    
    SELECT currval('visits_visitid_seq') INTO newid;
    
    RETURN newid;
END;
$$ LANGUAGE plpgsql;

