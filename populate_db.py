#!/usr/bin/env python
# encoding: utf-8
"""
populate_db.py

Created by Dr. H on 2010-06-28.
Copyright (c) 2010 UTHSC School of Health Information Sciences. All rights reserved.
"""

import sys
import os
import psycopg2
import random
from decimal import *

AGE_MIN=18
AGE_MAX=99
AGE_NORMAL=25
AGE_SIGMA=20

#VISITS_PER_PATIENT_NORMAL=3
#VISITS_PER_PATIENT_SIGMA=5
VISITS_PER_PATIENT_PARETO_ALPHA=1

LABS_PER_CONDITION_NORMAL=2
LABS_PER_CONDITION_SIGMA=2

EXTRA_LABS_PER_VISIT_NORMAL=1
EXTRA_LABS_PER_VISIT_SIGMA=3

OLDEST_VISIT=10*365 # In days ago

# Probabilities
PROVIDER_NOT_AVAILABLE=0.07
MAX_PROBABILTY_PROVIDER_MESSES_UP_PER_VISIT=0.01
PROBABILITY_CONDITION_MISSED=0.3
PROBABILITY_CONDITION_ADDED=0.3

#Probability another lab is abnormal
PROBABILITY_SPURIOUS_ABNORMAL_LAB=0.01

def normal_random_with_min_bounds(normal, sigma, min_acceptable=0.0):
    variable=min_acceptable-1
    while variable<min_acceptable:
        variable=random.normalvariate(normal, sigma)
    return variable

def normal_int_with_min_bounds(normal, sigma, min_acceptable=0):
    return int(normal_random_with_min_bounds(normal, sigma, min_acceptable))
    
class lab_test(object):
    def __init__(self, name, minimum, maximum, abs_min=0.0):
        self._name=name
        self._minimum=float(minimum)
        self._maximum=float(maximum)
        self._normal=float(self._minimum+self._maximum)/2.0
        self._sigma=abs(float(self._maximum-self._minimum))/4.0
        self._abs_min=0.0
    def name():
        doc = "The name property."
        def fget(self):
            return self._name
        return locals()
    name = property(**name())
    def minimum():
        doc = "The minimum property."
        def fget(self):
            return self._minimum
        return locals()
    minimum = property(**minimum())
    def maximum():
        doc = "The maximum property."
        def fget(self):
            return self._maximum
        return locals()
    maximum = property(**maximum())
    def normal_result(self):
        return normal_random_with_min_bounds(self._normal, 
                                             self._sigma, 
                                             self._abs_min)
    def abnormal_result(self):
        # Low or high?
        if random.random() < 0.5:
            # Low
            return normal_random_with_min_bounds(self._minimum-3.0*self._sigma,
                                                 self._sigma,
                                                 self._abs_min)
        else:
            # High
            return normal_random_with_min_bounds(self._maximum+3.0*self._sigma,
                                                 self._sigma,
                                                 self._abs_min)
    def __repr__(self):
        return "<Lab test: %s>" % (self.name,)
    def __eq__(self, other):
        return self._name==other._name
                
class disease(object):
    def __init__(self, code, name, prevalence):
        self._name=name
        self._code=code
        self._prevalence=float(prevalence)
    def name():
        doc = "The name property."
        def fget(self):
            return self._name
        return locals()
    name = property(**name())
    def code():
        doc = "The code property."
        def fget(self):
            return self._code
        return locals()
    code = property(**code())
    def prevalence():
        doc = "The prevalence property."
        def fget(self):
            return self._prevalence
        return locals()
    prevalence = property(**prevalence())
    def __repr__(self):
        return "<Condition %s: %s>" % (self.code, self.name)
    def __eq__(self, other):
        return self._code==other._code

def setup_connection(DBNAME):
    return psycopg2.connect('dbname=%s' % (DBNAME,))

def get_valid_providers(connection):
    cur=connection.cursor()
    cur.execute("SELECT name FROM providers")
    return [x[0] for x in cur.fetchall()]

def get_valid_races(connection):
    cur=connection.cursor()
    cur.execute("SELECT name FROM races")
    return [x[0] for x in cur.fetchall()]
    
def get_valid_lab_tests(connection):
    cur=connection.cursor()
    cur.execute("SELECT lab_testid, normal_min, normal_max FROM lab_tests")
    return [lab_test(*x) for x in cur.fetchall()]
    
def get_diseases(connection):
    cur=connection.cursor()
    cur.execute("SELECT code, name, prevalence FROM icd_codes")
    return [disease(*x) for x in cur.fetchall()]
    
def create_patient(cursor, races):
    age=0
    while age < AGE_MIN or age > AGE_MAX:
        age=int(random.normalvariate(AGE_NORMAL, AGE_SIGMA))
    cursor.execute("SELECT NewPatient(%s, %s)", (age, random.choice(races)))
    return cursor.fetchone()[0]
    
def chance_providers_mess_up(providers):
    """Creates a dictionary specifying the probability that each provider makes
    a diagnostic mistake."""
    prob={}
    for provider in providers:
        prob[provider]=random.random() * MAX_PROBABILTY_PROVIDER_MESSES_UP_PER_VISIT
    return prob

def generate_order_sets(conditions, labs):
    labs_per_condition={}
    for c in conditions:
        num_labs=normal_int_with_min_bounds(LABS_PER_CONDITION_NORMAL, LABS_PER_CONDITION_SIGMA)
        labs_per_condition[c]=set(random.sample(labs, num_labs))
    return labs_per_condition

def decide_which_lab_is_abnormal_for_each_condition(order_sets):
    abnormal_labs={}
    for o in order_sets:
        if len(order_sets[o])>0:
            abnormal_labs[o]=random.choice(list(order_sets[o]))
    return abnormal_labs
    
def visits_one_patient():
    #return normal_int_with_min_bounds(VISITS_PER_PATIENT_NORMAL, VISITS_PER_PATIENT_SIGMA, 1)
    return int(random.paretovariate(VISITS_PER_PATIENT_PARETO_ALPHA))

def labs_one_visit(patient_conditions, order_sets, lab_tests):
    labs=set([])
    for c in patient_conditions:
        labs|=order_sets[c]
    # add an extra lab here or there
    extra_labs=normal_int_with_min_bounds(EXTRA_LABS_PER_VISIT_NORMAL, EXTRA_LABS_PER_VISIT_SIGMA)
    try:
        labs|=set(random.sample(lab_tests, extra_labs))
    except ValueError:
        # Tried to sample too many
        labs|=set(lab_tests)
    return labs
    
def assign_lab_values(labs_this_patient, conditions, abnormal_labs):
    labs_with_values=[]
    to_be_abnormal=set([])
    for c in conditions:
        try:
            to_be_abnormal.add(abnormal_labs[c])
        except KeyError:
            # This condition has no abnormal labs
            pass
    for l in labs_this_patient:
        if l in to_be_abnormal:
            labs_with_values.append((l, l.abnormal_result()))
        else:
            if random.random()<PROBABILITY_SPURIOUS_ABNORMAL_LAB:
                labs_with_values.append((l, l.abnormal_result()))
            else:
                labs_with_values.append((l, l.normal_result()))
    return labs_with_values
        
def save_visit(cursor, patient_number, provider, date):
    cursor.execute("SELECT NewVisit(%s, %s, %s)", (provider, patient_number, date))
    return cursor.fetchone()[0]

def save_problems(cursor, visitid, conditions):
    for c in conditions:
        cursor.execute("INSERT INTO problems (visit, icd_code) VALUES (%s, %s)", (visitid, c.code))
    return

def save_labs(cursor, visitid, labs):
    for l in labs:
        cursor.execute("INSERT INTO labs (visit, lab_test, value) VALUES (%s, %s, %s)", (visitid, l[0].name, l[1]))
    return
    
def save_patient_ground_truth(cursor, patientid, patient_conditions):
    for c in patient_conditions:
        cursor.execute("INSERT INTO patients_ground_truth (patient, icd_code) VALUES (%s, %s)", (patientid, c.code))
    return
    
def generate_patient_conditions(diseases):
    conditions=[]
    for d in diseases:
        if random.random() < d.prevalence:
            conditions.append(d)
    return conditions
    
def generate_patient_history(cursor, patient_number, diseases, providers, lab_tests, order_sets, abnormal_labs):
    # This is what the patient actually has
    patient_conditions=generate_patient_conditions(diseases)
    save_patient_ground_truth(cursor, patient_number, patient_conditions)
    patient_provider=random.choice(providers.keys())
    num_visits=visits_one_patient()
    max_visit_spacing=OLDEST_VISIT/num_visits
    visit_date=int(random.random()*max_visit_spacing*num_visits)
    for i in xrange(num_visits):
        this_visits_provider=patient_provider
        if random.random() < PROVIDER_NOT_AVAILABLE:
            # Replaced by someone else for this visit
            this_visits_provider=random.choice(providers.keys())
        this_visits_conditions=patient_conditions[:] # Copy
        if random.random() < providers[this_visits_provider]:
            # Provider screwed up.
            if random.random() < PROBABILITY_CONDITION_MISSED:
                if len(this_visits_conditions)>0:
                    this_visits_conditions.remove(random.choice(this_visits_conditions))
            if random.random() < PROBABILITY_CONDITION_ADDED:
                # Add a new condition to this visit
                this_visits_conditions.append(random.choice([x for x in diseases if x not in this_visits_conditions]))
        visit_id=save_visit(cursor, patient_number, this_visits_provider, visit_date)
        visit_date-=int(random.random() * max_visit_spacing)
        save_problems(cursor, visit_id, this_visits_conditions)
        this_visits_labs=labs_one_visit(this_visits_conditions, order_sets, lab_tests)
        lab_results=assign_lab_values(this_visits_labs, this_visits_conditions, abnormal_labs)
        save_labs(cursor, visit_id, lab_results)
    return
    
def main():
    DBNAME=sys.argv[1]
    NUM_PATIENTS=int(sys.argv[2])
    random.seed()
    conn=setup_connection(DBNAME)
    providers=get_valid_providers(conn)
    races=get_valid_races(conn)
    lab_tests=get_valid_lab_tests(conn)
    diseases=get_diseases(conn)
    print "Providers=", providers
    failure_rates=chance_providers_mess_up(providers)
    print "Failure rates=", failure_rates
    print "Diseases=", diseases
    print "Races=", races
    print "Lab tests=", lab_tests
    order_sets=generate_order_sets(diseases, lab_tests)
    print "Order sets=", order_sets
    abnormal_labs=decide_which_lab_is_abnormal_for_each_condition(order_sets)
    print "Abnormal labs=", abnormal_labs
    print "Inserting %d patients" % NUM_PATIENTS
    cur=conn.cursor()
    for x in xrange(NUM_PATIENTS): # REPLACE WITH NUM_PATIENTS
        this_patient=create_patient(cur, races)
        generate_patient_history(cur, this_patient, diseases, failure_rates, lab_tests, order_sets, abnormal_labs)
        if x % 1000==0:
            # Commmit every 1000
            conn.commit()
    conn.commit()
    
if __name__ == '__main__':
    main()

