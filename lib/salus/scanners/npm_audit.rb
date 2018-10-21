require 'json'
require 'salus/scanners/base'

# NPM Audit scanner - looks for CVEs in node dependencies.

module Salus::Scanners
  class NPMAudit < Base
    ADVISORY_URL_REGEX = %r{^https://nodesecurity.io/advisories/(\d+)$}

    def run
      exceptions = @config['exceptions']

      created_package_lock = false
      if !@repository.package_lock_json_present?
        log('Generating a temporary package-lock.json...')

        Dir.chdir(@repository.path_to_repo) do
          shell_return = run_shell('npm install --package-lock-only')

          if !shell_return.exit_status.success?
            log("STDERR:\n```\n#{shell_return.stderr}\n```")
            report_failure
            return
          end

          created_package_lock = true
        end
      end

      Dir.chdir(@repository.path_to_repo) do
        shell_return = run_shell('npm audit --json')

        if shell_return.exit_status.success?
          report_success
        else
          # Parse output
          npm_audit_report = JSON.parse(shell_return.stdout)
          report_stdout(shell_return.stdout)

          # Report scan output
          report_info('npm_audit_output', npm_audit_report)

          # Report ignored advisories after validating the keys all exist
          exceptions&.each do |exception|
            if exception.keys.sort != %w[advisory_id changed_by notes]
              report_error("The exception #{exception} doesn't have a proper format! Please ensure"\
              ' that each exception has an `advisory_id`, `changed_by`, and `notes` field!')
            end
            report_info('exceptions', exception)
          end

          exception_ids = exceptions&.map { |x| x['advisory_id'] } || []
          active_vuln_ids = npm_audit_report['advisories'].keys - exception_ids

          active_vuln_ids.empty? ? report_success : report_failure
        end

        # Cleanup, mostly for local dev since we run in Docker normally
        File.delete('package-lock.json') if created_package_lock
      end
    end

    def should_run?
      @repository.package_json_present? ||
        @repository.package_lock_json_present? ||
        @repository.yarn_lock_present?
    end
  end
end
