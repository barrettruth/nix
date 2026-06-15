{ pkgs, lib }:
let
  mkR2Backup =
    {
      name,
      source,
      bucket,
      environmentFile,
      after ? [ ],
    }:
    {
      systemd.services."${name}-r2-backup" = {
        description = "Backup ${name} to Cloudflare R2";
        inherit after;
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = environmentFile;
        };
        path = [
          pkgs.awscli2
          pkgs.gawk
        ];
        script = ''
          : "''${R2_ACCESS_KEY_ID:?${name} R2 backup secret is missing R2_ACCESS_KEY_ID}"
          : "''${R2_SECRET_ACCESS_KEY:?${name} R2 backup secret is missing R2_SECRET_ACCESS_KEY}"
          : "''${R2_ENDPOINT:?${name} R2 backup secret is missing R2_ENDPOINT}"

          export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
          export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
          ENDPOINT="$R2_ENDPOINT"
          DATE=$(date +%Y-%m-%d)

          aws s3 cp ${source} \
            "s3://${bucket}/$DATE/$(basename ${source})" \
            --endpoint-url "$ENDPOINT"

          CUTOFF=$(date -d '30 days ago' +%Y-%m-%d)
          aws s3 ls s3://${bucket}/ --endpoint-url "$ENDPOINT" \
            | awk '{print $2}' | tr -d '/' \
            | while read dir; do
                if [ "$dir" \< "$CUTOFF" ]; then
                  aws s3 rm "s3://${bucket}/$dir" --recursive --endpoint-url "$ENDPOINT"
                fi
              done
        '';
      };

      systemd.timers."${name}-r2-backup" = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };

  mkNextjsApp =
    {
      name,
      dir,
      user,
      group,
      port,
      environment,
      description ? name,
      environmentFile ? null,
    }:
    {
      users.users.${user} = {
        isSystemUser = true;
        home = dir;
        inherit group;
      };

      users.groups.${group} = { };

      systemd.tmpfiles.rules = [ "d ${dir} 0755 ${user} ${group} -" ];

      systemd.services.${name} = {
        inherit description;
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "${dir}/.next/standalone/server.js";
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = dir;
          ExecStart = "${pkgs.nodejs_22}/bin/node .next/standalone/server.js";
          Restart = "on-failure";
          RestartSec = 5;
          User = user;
          Group = group;
          StateDirectory = name;
        }
        // lib.optionalAttrs (environmentFile != null) {
          EnvironmentFile = environmentFile;
        };
        environment = {
          NODE_ENV = "production";
          PORT = toString port;
          HOSTNAME = "127.0.0.1";
        }
        // environment;
      };
    };

  mkDeployService =
    {
      name,
      dir,
      user,
      group,
      after ? [ "network-online.target" ],
      wants ? [ "network-online.target" ],
      environment ? { },
      safeDirectories ? [ ],
      postScript ? "",
      restartUnit ? null,
    }:
    {
      systemd.services."${name}-deploy" = {
        description = "Build and release ${name} from ${dir}";
        inherit after wants;
        path = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gitMinimal
          pkgs.nodejs_22
          pkgs.pnpm
        ];
        environment = {
          HOME = if user == "root" then "/root" else dir;
          NODE_ENV = "production";
          npm_config_manage_package_manager_versions = "false";
          COREPACK_ENABLE_AUTO_PIN = "0";
        }
        // environment;
        serviceConfig = {
          Type = "oneshot";
          User = user;
          Group = group;
          WorkingDirectory = dir;
          ExecStart = pkgs.writeShellScript "${name}-deploy" ''
            set -euo pipefail
            ${lib.concatMapStringsSep "\n" (
              d: "git config --global --add safe.directory \"${d}\""
            ) safeDirectories}
            bash ${dir}/scripts/deploy.sh
            ${postScript}
          '';
        };
      };

      security.polkit.enable = true;
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units") {
            var unit = action.lookup("unit");
            if (subject.user == "gitea-runner" && unit == "${name}-deploy.service") {
              return polkit.Result.YES;
            }
            ${lib.optionalString (restartUnit != null) ''
              if (subject.user == "${user}" && unit == "${restartUnit}") {
                return polkit.Result.YES;
              }
            ''}
          }
        });
      '';
    };
in
{
  inherit mkR2Backup mkNextjsApp mkDeployService;
}
