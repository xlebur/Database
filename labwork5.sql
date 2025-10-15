DROP TABLE IF EXISTS
    order_details,
    orders_ecom,
    products_ecom,
    customers_ecom,
    order_items,
    orders,
    products_fk,
    categories,
    books,
    authors,
    publishers,
    employees_dept,
    departments,
    student_courses,
    course_enrollments,
    users,
    inventory,
    customers,
    bookings,
    products_catalog,
    employees
CASCADE;

CREATE TABLE employees (
    employee_id INTEGER,
    first_name TEXT,
    last_name TEXT,
    age INTEGER CHECK (age BETWEEN 18 AND 65),
    salary NUMERIC CHECK (salary > 0)
);

INSERT INTO employees VALUES (1,'Omar','URaz',19,5000);
INSERT INTO employees VALUES (2,'Marat','Tolibai',20,8500);


CREATE TABLE products_catalog (
    product_id     INTEGER,
    product_name   TEXT,
    regular_price  NUMERIC,
    discount_price NUMERIC,
    CONSTRAINT valid_discount CHECK (
        regular_price > 0 AND
        discount_price > 0 AND
        discount_price < regular_price
    )
);

INSERT INTO products_catalog VALUES (1,'Laptop',1200,1000);
INSERT INTO products_catalog VALUES (2,'Phone',800,700);


CREATE TABLE bookings (
    booking_id     INTEGER,
    check_in_date  DATE,
    check_out_date DATE,
    num_guests     INTEGER CHECK (num_guests BETWEEN 1 AND 10),
    CHECK (check_out_date > check_in_date)
);

INSERT INTO bookings VALUES (1,'2025-01-01','2025-01-05',2);
INSERT INTO bookings VALUES (2,'2025-03-10','2025-03-12',4);


CREATE TABLE customers (
    customer_id       INTEGER  NOT NULL,
    email             TEXT     NOT NULL,
    phone             TEXT,
    registration_date DATE     NOT NULL
);

INSERT INTO customers VALUES (1,'a@x.com','123-456','2025-01-01');
INSERT INTO customers VALUES (2,'b@y.com',NULL,'2025-02-15');


CREATE TABLE inventory (
    item_id      INTEGER  NOT NULL,
    item_name    TEXT     NOT NULL,
    quantity     INTEGER  NOT NULL CHECK (quantity >= 0),
    unit_price   NUMERIC  NOT NULL CHECK (unit_price > 0),
    last_updated TIMESTAMP NOT NULL
);

INSERT INTO inventory VALUES (1,'Keyboard',10,50.00,NOW());
INSERT INTO inventory VALUES (2,'Monitor',5,200.00,NOW());

CREATE TABLE users (
    user_id    INTEGER,
    username   TEXT UNIQUE,
    email      TEXT UNIQUE,
    created_at TIMESTAMP
);

INSERT INTO users VALUES (1,'omar','o@ex.com',NOW());
INSERT INTO users VALUES (2,'ali','a@ex.com',NOW());

CREATE TABLE course_enrollments (
    enrollment_id INTEGER,
    student_id    INTEGER,
    course_code   TEXT,
    semester      TEXT,
    CONSTRAINT unique_student_course_sem UNIQUE (student_id, course_code, semester)
);

INSERT INTO course_enrollments VALUES (1,1001,'BD201','Spring');
INSERT INTO course_enrollments VALUES (2,1001,'BD201','Fall');

ALTER TABLE users
    ADD CONSTRAINT unique_username UNIQUE (username),
    ADD CONSTRAINT unique_email    UNIQUE (email);

CREATE TABLE departments (
    dept_id   INTEGER PRIMARY KEY,
    dept_name TEXT NOT NULL,
    location  TEXT
);

INSERT INTO departments VALUES (1,'IT','Astana');
INSERT INTO departments VALUES (2,'HR','Almaty');
INSERT INTO departments VALUES (3,'Finance','Atyrau');

CREATE TABLE student_courses (
    student_id      INTEGER,
    course_id       INTEGER,
    enrollment_date DATE,
    grade           TEXT,
    PRIMARY KEY (student_id, course_id)
);

INSERT INTO student_courses VALUES (1,10,'2025-01-10','A');
INSERT INTO student_courses VALUES (1,20,'2025-01-12','B');

/*
UNIQUE vs PRIMARY KEY:
• Both prevent duplicate values.
• PRIMARY KEY also implies NOT NULL.
• A table can have only one PRIMARY KEY but multiple UNIQUE constraints.

Single-column vs Composite PK:
• Use single column when one field uniquely identifies a row.
• Use composite when the combination of fields must be unique.

Why a table can have only one PRIMARY KEY but multiple UNIQUE constraints?
• A table can have only one PRIMARY KEY because it represents the single official unique identity of rows.
• It can have multiple UNIQUE constraints because there may be several alternate unique attributes, but only one is the main key used for relationships and integrity.
 */

 CREATE TABLE employees_dept (
    emp_id   INTEGER PRIMARY KEY,
    emp_name TEXT NOT NULL,
    dept_id  INTEGER REFERENCES departments(dept_id),
    hire_date DATE
);

INSERT INTO employees_dept VALUES (1,'Arman',1,'2024-01-01');
INSERT INTO employees_dept VALUES (2,'Mira',2,'2024-05-05');

CREATE TABLE authors (
    author_id   INTEGER PRIMARY KEY,
    author_name TEXT NOT NULL,
    country     TEXT
);

CREATE TABLE publishers (
    publisher_id   INTEGER PRIMARY KEY,
    publisher_name TEXT NOT NULL,
    city           TEXT
);

CREATE TABLE books (
    book_id         INTEGER PRIMARY KEY,
    title           TEXT NOT NULL,
    author_id       INTEGER REFERENCES authors(author_id),
    publisher_id    INTEGER REFERENCES publishers(publisher_id),
    publication_year INTEGER,
    isbn            TEXT UNIQUE
);

INSERT INTO authors VALUES (1,'Tolstoy','Russia');
INSERT INTO authors VALUES (2,'Rowling','UK');

INSERT INTO publishers VALUES (1,'Penguin','London');
INSERT INTO publishers VALUES (2,'Vintage','NY');

INSERT INTO books VALUES (1,'War and Peace',1,1,1869,'ISBN001');
INSERT INTO books VALUES (2,'Harry Potter',2,2,1997,'ISBN002');

CREATE TABLE categories (
    category_id   INTEGER PRIMARY KEY,
    category_name TEXT NOT NULL
);

CREATE TABLE products_fk (
    product_id   INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category_id  INTEGER REFERENCES categories(category_id) ON DELETE RESTRICT
);

CREATE TABLE orders (
    order_id   INTEGER PRIMARY KEY,
    order_date DATE NOT NULL
);

CREATE TABLE order_items (
    item_id   INTEGER PRIMARY KEY,
    order_id  INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products_fk(product_id),
    quantity  INTEGER CHECK (quantity > 0)
);

INSERT INTO categories VALUES (1,'Electronics');
INSERT INTO products_fk VALUES (10,'TV',1);
INSERT INTO orders VALUES (100,'2025-01-10');
INSERT INTO order_items VALUES (1000,100,10,2);

CREATE TABLE customers_ecom (
    customer_id      INTEGER PRIMARY KEY,
    name             TEXT NOT NULL,
    email            TEXT UNIQUE NOT NULL,
    phone            TEXT,
    registration_date DATE NOT NULL
);

CREATE TABLE products_ecom (
    product_id     INTEGER PRIMARY KEY,
    name           TEXT NOT NULL,
    description    TEXT,
    price          NUMERIC CHECK (price >= 0),
    stock_quantity INTEGER CHECK (stock_quantity >= 0)
);

CREATE TABLE orders_ecom (
    order_id     INTEGER PRIMARY KEY,
    customer_id  INTEGER REFERENCES customers_ecom(customer_id) ON DELETE CASCADE,
    order_date   DATE NOT NULL,
    total_amount NUMERIC CHECK (total_amount >= 0),
    status       TEXT CHECK (status IN ('pending','processing','shipped','delivered','cancelled'))
);

CREATE TABLE order_details (
    order_detail_id INTEGER PRIMARY KEY,
    order_id        INTEGER REFERENCES orders_ecom(order_id) ON DELETE CASCADE,
    product_id      INTEGER REFERENCES products_ecom(product_id),
    quantity        INTEGER CHECK (quantity > 0),
    unit_price      NUMERIC CHECK (unit_price > 0)
);

INSERT INTO customers_ecom VALUES (1,'Ali','ali@ex.com','123','2025-01-01');
INSERT INTO customers_ecom VALUES (2,'Mira','mira@ex.com',NULL,'2025-02-10');

INSERT INTO products_ecom VALUES (1,'Phone','Smartphone',800,10);
INSERT INTO products_ecom VALUES (2,'Laptop','Gaming laptop',1500,5);

INSERT INTO orders_ecom VALUES (1,1,'2025-03-01',2300,'pending');
INSERT INTO orders_ecom VALUES (2,2,'2025-03-05',1500,'processing');

INSERT INTO order_details VALUES (1,1,1,1,800);
INSERT INTO order_details VALUES (2,1,2,1,1500);
INSERT INTO order_details VALUES (3,2,2,1,1500);