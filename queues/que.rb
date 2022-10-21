$pg.async_exec "DROP TABLE IF EXISTS que_jobs, que_values, que_lockers CASCADE"
$pg.async_exec "DROP FUNCTION IF EXISTS que_validate_tags, que_job_notify, que_state_notify"

ActiveRecord::Base.establish_connection(DATABASE_URL)
ActiveRecord::Base.connection.raw_connection.async_exec "SET SESSION synchronous_commit = #{SYNCHRONOUS_COMMIT}"

Que.connection = ActiveRecord
Que.migrate!(version: 7)

$pg.async_exec <<-SQL
  INSERT INTO que_jobs (job_class, priority, job_schema_version)
  SELECT 'QuePerpetualJob', 1, 1
  FROM generate_Series(1,#{JOB_COUNT}) AS i;
SQL

class QuePerpetualJob < Que::Job
  def run
    Que.execute "begin"
    self.class.enqueue
    Que.execute "commit"
  end
end

QUEUES[:que] = {
  :setup => -> { Que.connection = NEW_PG.call },
  :work  => -> { Que::Job.work }
}
