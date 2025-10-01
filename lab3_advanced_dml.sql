CREATE DATABASE advanced_lab;

CREATE TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    department VARCHAR(50) DEFAULT 'General',
    salary INTEGER DEFAULT 40000,
    hire_date DATE,
    status VARCHAR(20) DEFAULT 'Active'
);

CREATE TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(100),
    budget INTEGER,
    manager_id INTEGER
);

CREATE TABLE projects (
    project_id SERIAL PRIMARY KEY,
    project_name VARCHAR(100),
    dept_id INTEGER,
    start_date DATE,
    end_date DATE,
    budget INTEGER
);

INSERT INTO employees (first_name, last_name, department)
VALUES ('John', 'Doe', 'IT');

INSERT INTO employees (first_name, last_name)
VALUES ('Jane', 'Smith');

INSERT INTO departments (dept_name, budget, manager_id)
VALUES
  ('HR', 50000, 1),
  ('IT', 120000, 2),
  ('Sales', 90000, 3);

INSERT INTO employees (first_name, last_name, salary, hire_date, department)
VALUES ('Alice', 'Brown', 50000 * 1.1, CURRENT_DATE, 'Finance');

UPDATE employees
SET salary = salary * 1.1
WHERE department IS NOT NULL;

UPDATE employees
SET status = 'Senior'
WHERE salary > 60000
  AND hire_date < '2020-01-01';

UPDATE employees
SET department = CASE
    WHEN salary > 80000 THEN 'Management'
    WHEN salary BETWEEN 50000 AND 80000 THEN 'Senior'
    ELSE 'Junior'
END
WHERE salary IS NOT NULL;

UPDATE employees
SET department = DEFAULT
WHERE status = 'Inactive';

UPDATE departments d
SET budget = (
    SELECT AVG(salary) * 1.2
    FROM employees e
    WHERE e.department = d.dept_name
)
WHERE EXISTS (
    SELECT 1 FROM employees e WHERE e.department = d.dept_name
);

UPDATE employees
SET salary = salary * 1.15,
    status = 'Promoted'
WHERE department = 'Sales';

DELETE FROM employees
WHERE status = 'Terminated';

DELETE FROM employees
WHERE salary < 40000
  AND hire_date > '2023-01-01'
  AND department IS NULL;

DELETE FROM departments
WHERE dept_name NOT IN (
    SELECT DISTINCT department
    FROM employees
    WHERE department IS NOT NULL
);


DELETE FROM projects
WHERE end_date < '2023-01-01'
RETURNING *;

INSERT INTO employees (first_name, last_name, salary, department)
VALUES ('NullGuy', 'Test', NULL, NULL);

UPDATE employees
SET department = 'Unassigned'
WHERE department IS NULL;

DELETE FROM employees
WHERE salary IS NULL OR department IS NULL;

INSERT INTO employees (first_name, last_name, department, hire_date)
VALUES ('Robert', 'Lee', 'IT', CURRENT_DATE)
RETURNING emp_id, first_name || ' ' || last_name AS full_name;

UPDATE employees
SET salary = salary + 5000
WHERE department = 'IT'
RETURNING emp_id, salary - 5000 AS old_salary, salary AS new_salary;

DELETE FROM employees
WHERE hire_date < '2020-01-01'
RETURNING *;

INSERT INTO employees (first_name, last_name, department, hire_date)
SELECT 'Michael', 'Jordan', 'Sports', CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM employees
    WHERE first_name = 'Michael' AND last_name = 'Jordan'
);

-- 24. UPDATE with JOIN logic using subqueries
UPDATE employees e
SET e.salary = e.salary * CASE
    WHEN (SELECT d.budget
          FROM departments d
          WHERE d.dept_name = e.department) > 100000
        THEN 1.10
    ELSE 1.05
END;


INSERT INTO employees (first_name, last_name, department, hire_date, salary)
VALUES
  ('Emp1', 'Bulk', 'HR', CURRENT_DATE, 40000),
  ('Emp2', 'Bulk', 'HR', CURRENT_DATE, 42000),
  ('Emp3', 'Bulk', 'IT', CURRENT_DATE, 45000),
  ('Emp4', 'Bulk', 'Sales', CURRENT_DATE, 47000),
  ('Emp5', 'Bulk', 'Sales', CURRENT_DATE, 48000);

UPDATE employees
SET salary = salary * 1.1
WHERE last_name = 'Bulk';

CREATE TABLE employee_archive AS
TABLE employees WITH NO DATA;

INSERT INTO employee_archive
SELECT * FROM employees WHERE status = 'Inactive';

DELETE FROM employees
WHERE status = 'Inactive';

UPDATE projects p
SET end_date = end_date + INTERVAL '30 days'
WHERE budget > 50000
  AND (
      SELECT COUNT(*) FROM employees e
      WHERE e.department = (
          SELECT dept_name FROM departments d WHERE d.dept_id = p.dept_id
      )
  ) > 3;
