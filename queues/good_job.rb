require 'rails'
require 'action_controller/railtie'

class App < ::Rails::Application;
  config.eager_load = true
end

Rails.logger = Logger.new(nil)
App.initialize!

$pg.async_exec <<-SQL
  DROP TABLE IF EXISTS good_jobs;

  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  CREATE TABLE good_jobs (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    active_job_id uuid,
    concurrency_key text,
    cron_key text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    queue_name text,
    priority integer,
    serialized_params jsonb,
    scheduled_at timestamp without time zone,
    performed_at timestamp without time zone,
    finished_at timestamp without time zone,
    error text
  );

  CREATE INDEX index_good_jobs_on_queue_name_and_scheduled_at ON public.good_jobs USING btree (queue_name, scheduled_at) WHERE (finished_at IS NULL);
  CREATE INDEX index_good_jobs_on_scheduled_at ON public.good_jobs USING btree (scheduled_at) WHERE (finished_at IS NULL);

  INSERT INTO "good_jobs" ("active_job_id", "concurrency_key", "cron_key", "created_at", "updated_at", "scheduled_at", "queue_name", "priority", "serialized_params")
  SELECT gen_random_uuid(), NULL, NULL, NOW(), NOW(), NOW(), 'default', 0, '{\"job_class\":\"ExampleJob\",\"job_id\":\"31f0ac5d-185a-4cbb-a22b-64c9b9839617\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":0,\"arguments\":[],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2020-09-21T14:16:16Z\"}'
  FROM generate_Series(1,#{JOB_COUNT}) AS i;
SQL

class GoodJobPerpetualJob < ActiveJob::Base
  def perform
  end
end

ActiveJob::Base.logger = nil
GoodJob::Execution.primary_key = :id

QUEUES[:good_job] = {
  :setup => -> {
    ActiveRecord::Base.establish_connection(DATABASE_URL)
    db_config = ActiveRecord::Base.configurations.configs_for.first.configuration_hash.dup
    db_config[:pool] = 20

    # Re-establish the connection with the new configuration
    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::Base.connection.raw_connection.async_exec "SET SESSION synchronous_commit = #{SYNCHRONOUS_COMMIT}"
  },
  :work => -> { GoodJob::Execution.perform_with_advisory_lock }
}
