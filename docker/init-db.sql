-- Initialize all databases for HyperSense multi-database setup
-- This script runs automatically when the PostgreSQL container is first created

-- Development databases
CREATE DATABASE hypersense_development_cache;
CREATE DATABASE hypersense_development_queue;
CREATE DATABASE hypersense_development_cable;

-- Test databases
CREATE DATABASE hypersense_test;
CREATE DATABASE hypersense_test_cache;
CREATE DATABASE hypersense_test_queue;
CREATE DATABASE hypersense_test_cable;

-- Production databases
CREATE DATABASE hypersense_production;
CREATE DATABASE hypersense_production_cache;
CREATE DATABASE hypersense_production_queue;
CREATE DATABASE hypersense_production_cable;

-- Grant privileges to hypersense user on all databases
-- Development
GRANT ALL PRIVILEGES ON DATABASE hypersense_development TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_development_cache TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_development_queue TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_development_cable TO hypersense;
-- Test
GRANT ALL PRIVILEGES ON DATABASE hypersense_test TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_test_cache TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_test_queue TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_test_cable TO hypersense;
-- Production
GRANT ALL PRIVILEGES ON DATABASE hypersense_production TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_production_cache TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_production_queue TO hypersense;
GRANT ALL PRIVILEGES ON DATABASE hypersense_production_cable TO hypersense;
