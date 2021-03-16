require 'skiplock'

$pg.async_exec <<-SQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS skiplock;
DROP TABLE IF EXISTS skiplock.jobs;
CREATE TABLE skiplock.jobs(
  id uuid DEFAULT public.gen_random_uuid() NOT NULL,
  job_class varchar NOT NULL,
  cron varchar,
  queue_name varchar,
  locale varchar,
  timezone varchar,
  priority integer,
  executions integer,
  exception_executions jsonb,
  data jsonb,
  expired_at timestamp without time zone,
  finished_at timestamp without time zone,
  scheduled_at timestamp without time zone,
  created_at timestamp(6) without time zone DEFAULT NOW() NOT NULL,
  updated_at timestamp(6) without time zone DEFAULT NOW() NOT NULL
);
CREATE INDEX jobs_index ON skiplock.jobs(scheduled_at ASC NULLS FIRST, priority ASC NULLS LAST, created_at ASC) WHERE expired_at IS NULL AND finished_at IS NULL;
INSERT INTO skiplock.jobs (job_class) SELECT 'SkiplockJob' FROM generate_Series(1,#{JOB_COUNT}) AS i;
SQL


class SkiplockJob < ActiveJob::Base
  def perform
  end
end

ActiveJob::Base.logger = nil

QUEUES[:skiplock] = {
  :setup => -> {
    ActiveRecord::Base.establish_connection(DATABASE_URL)
    ActiveRecord::Base.connection.raw_connection.async_exec "SET SESSION synchronous_commit = #{SYNCHRONOUS_COMMIT}"
  },
  :work => -> { Skiplock::Job.dispatch }
}
