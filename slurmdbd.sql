CREATE DATABASE slurm_accounting;
CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'abc123slurmdbd';
GRANT ALL PRIVILEGES ON slurm_accounting.* TO 'slurm'@'localhost';
