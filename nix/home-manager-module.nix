{ lib
, pkgs
, config
, ...
}:

with lib;
let
  cfg = config.programs.smos;

  mergeListRecursively = pkgs.callPackage ./merge-lists-recursively.nix { };

  toYamlFile = pkgs.callPackage ./to-yaml.nix { };

in
{
  options.programs.smos = {
    enable = mkEnableOption "Smos";
    smosReleasePackages = mkOption {
      description = "The smosPackages attribute defined in the nix/overlay.nix file in the smos repository.";
      type = types.attrs;
      default = (import ./pkgs.nix { }).smosReleasePackages;
    };
    config = mkOption {
      description = "The contents of the config file, as an attribute set. This will be translated to Yaml and put in the right place along with the rest of the options defined in this submodule.";
      type = types.attrs;
      default = { };
    };
    workflowDir = mkOption {
      description = "Smos' workflow directory";
      type = types.str;
      default = config.home.homeDirectory + "/workflow";
    };
    backup = mkOption {
      description = "Periodic local backups of the workflow directory";
      type = types.nullOr (types.submodule {
        options = {
          enable = mkEnableOption "Smos backups";
          backupDir = mkOption {
            type = types.str;
            default = "${config.xdg.dataHome}/smos/backup";
            description = "The directory to backup to";
          };
        };
      });
      default = null;
    };
    sync = mkOption {
      description = "Periodic local backups of the workflow directory";
      type = types.nullOr (types.submodule {
        options = {
          enable = mkEnableOption "Smos syncing";
          server-url = mkOption {
            type = types.str;
            example = "api.smos.cs-syd.eu";
            description = "The url of the sync server";
          };
          username = mkOption {
            type = types.str;
            example = "syd";
            description = "The username to use when logging into the sync server";
          };
          password = mkOption {
            type = types.str;
            example = "hunter12";
            description = "The password to use when logging into the sync server";
          };
        };
      });
      default = null;
    };
    calendar = mkOption {
      description = "Periodic calendar imports";
      type = types.nullOr (types.submodule {
        options = {
          enable = mkEnableOption "Smos calendar importing";
          sources = mkOption {
            description = "The list of sources to import from";
            default = [ ];
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "Personal";
                  description = "The name of the source";
                };
                destination = mkOption {
                  type = types.str;
                  default = null;
                  example = "calendar/name.smos";
                  description = "The destination file within the workflow directory";
                };
                source = mkOption {
                  type = types.str;
                  default = null;
                  example = "https://calendar.google.com/calendar/ical/xxx.xxxxxxxxx%40gmail.com/private-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/basic.ics";
                  description = "The url to download the calendar from";
                };
              };
            });
          };
        };
      });
      default = null;
    };
    scheduler = mkOption {
      description = "Automatic scheduled project scheduling";
      type = types.nullOr (types.submodule {
        options = {
          enable = mkEnableOption "Smos scheduler activation";
          schedule = mkOption {
            description = "The schedule to activate";
            default = [ ];
            type = types.listOf (types.submodule {
              options = {
                description = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "Weekly tasks for work";
                  description = "A description of the schedule item. This is only used for logging and error messages.";
                };
                template = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "templates/weekly.smos";
                  description = "The relative path to the template in the workflow dir";
                };
                destination = mkOption {
                  type = types.str;
                  default = null;
                  example = "workflow/work-[ %Y-%V | monday ].smos";
                  description = "The template relative path to the destination in the workflow dir";
                };
                schedule = mkOption {
                  type = types.str;
                  default = null;
                  example = "0 12 * * 6"; # At 12:00 on saturday
                  description = "The cron schedule for when to activate this item";
                };
              };
            });
          };
        };
      });
      default = null;
    };
    notify = mkOption {
      description = "Desktop notifications";
      type = types.nullOr (types.submodule {
        options = {
          enable = mkEnableOption "Smos notification activation";
        };
      });
      default = null;
    };
  };
  config =
    let
      backupSmosName = "smos-backup";
      backupSmosService =
        {
          Unit =
            {
              Description = "Backup smos locally, to ${cfg.backup.backupDir}";
            };
          Service =
            {
              ExecStart =
                "${pkgs.writeShellScript "${backupSmosName}-service-ExecStart"
                  ''
                    export PATH="$PATH:${pkgs.coreutils}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin"
                    set -ex
                    backupdir="${cfg.backup.backupDir}"
                    mkdir -p "''${backupdir}"
                    backupfile="''${backupdir}/''$(date +%F_%T).tar.gz"
                    tar -cvzf "''${backupfile}" "${cfg.workflowDir}"
                  ''}";
              Type = "oneshot";
            };
        };
      backupSmosTimer =
        {
          Unit =
            {
              Description = "Backup smos locally every day";
            };
          Install =
            {
              WantedBy = [ "timers.target" ];
            };
          Timer =
            {
              OnCalendar = "*-*-* 00:00";
              Persistent = true;
              Unit = "${backupSmosName}.service";
            };
        };

      syncConfig = optionalAttrs (cfg.sync.enable or false) {
        sync = {
          server-url = cfg.sync.server-url;
          username = cfg.sync.username;
          password = cfg.sync.password;
        };
      };

      syncSmosName = "smos-sync";
      syncSmosService =
        {
          Unit =
            {
              Description = "Sync smos workflow";
              Wants = [ "network-online.target" ];
            };
          Service =
            {
              ExecStart =
                "${pkgs.writeShellScript "${syncSmosName}-service-ExecStart"
                  ''
                    exec ${cfg.smosReleasePackages.smos-sync-client}/bin/smos-sync-client sync
                  ''}";
              Type = "oneshot";
            };
        };
      syncSmosTimer =
        {
          Unit =
            {
              Description = "Sync smos every five minutes";
            };
          Install =
            {
              WantedBy = [ "timers.target" ];
            };
          Timer =
            {
              OnCalendar = "*:0/5";
              Persistent = true;
              Unit = "${syncSmosName}.service";
            };
        };

      calendarConfig =
        optionalAttrs (cfg.calendar.enable or false) {
          calendar = cfg.calendar;
        };


      calendarSmosName = "smos-calendar-import";
      calendarSmosService =
        {
          Unit =
            {
              Description = "Import calendars into smos";
              Wants = [ "network-online.target" ];
            };
          Service =
            {
              ExecStart =
                "${pkgs.writeShellScript "${calendarSmosName}-service-ExecStart"
                  ''
                    exec ${cfg.smosReleasePackages.smos-calendar-import}/bin/smos-calendar-import
                  ''}";
              Type = "oneshot";
            };
        };
      calendarSmosTimer =
        {
          Unit =
            {
              Description = "Import calendar into smos every day";
            };
          Install =
            {
              WantedBy = [ "timers.target" ];
            };
          Timer =
            {
              OnCalendar = "hourly";
              Persistent = true;
              Unit = "${calendarSmosName}.service";
            };
        };

      schedulerConfig =
        optionalAttrs (cfg.scheduler.enable or false) {
          scheduler = cfg.scheduler;
        };

      schedulerSmosName = "smos-scheduler";
      schedulerSmosService =
        {
          Unit =
            {
              Description = "smos-scheduler activation";
            };
          Service =
            {
              ExecStart =
                "${pkgs.writeShellScript "${schedulerSmosName}-service-ExecStart"
                  ''
                    set -e
                    ${cfg.smosReleasePackages.smos-scheduler}/bin/smos-scheduler check
                    exec ${cfg.smosReleasePackages.smos-scheduler}/bin/smos-scheduler schedule
                  ''}";
              Type = "oneshot";
            };
        };
      schedulerSmosTimer =
        {
          Unit =
            {
              Description = "Activate smos scheduler every day";
            };
          Install =
            {
              WantedBy = [ "timers.target" ];
            };
          Timer =
            {
              OnCalendar = "hourly";
              Persistent = true;
              Unit = "${schedulerSmosName}.service";
            };
        };

      notifySmosName = "smos-notify";
      notifySmosService =
        {
          Unit =
            {
              Description = "smos-notify activation";
            };
          Service =
            {
              ExecStart =
                "${pkgs.writeShellScript "${notifySmosName}-service-ExecStart"
                  ''
                    set -e
                    export PATH="$PATH:${pkgs.libnotify}/bin:${pkgs.sox}/bin"
                    exec ${cfg.smosReleasePackages.smos-notify}/bin/smos-notify
                  ''}";
              Type = "oneshot";
            };
        };
      notifySmosTimer =
        {
          Unit =
            {
              Description = "Activate smos notify every minute";
            };
          Install =
            {
              WantedBy = [ "timers.target" ];
            };
          Timer =
            {
              OnCalendar = "minutely";
              Persistent = true;
              Unit = "${notifySmosName}.service";
            };
        };

      smosConfig = mergeListRecursively [
        syncConfig
        calendarConfig
        schedulerConfig
        cfg.config
      ];

      # Convert the config file to pretty yaml, for readability.
      # The keys will not be in the "right" order but that's fine.
      smosConfigFile = toYamlFile "smos-config" smosConfig;

      services =
        (
          optionalAttrs (cfg.sync.enable or false)
            {
              "${syncSmosName}" = syncSmosService;
            }
          // optionalAttrs (cfg.backup.enable or false) {
            "${backupSmosName}" = backupSmosService;
          }
          // optionalAttrs (cfg.calendar.enable or false) {
            "${calendarSmosName}" = calendarSmosService;
          }
          // optionalAttrs (cfg.scheduler.enable or false) {
            "${schedulerSmosName}" = schedulerSmosService;
          }
          // optionalAttrs (cfg.notify.enable or false) {
            "${notifySmosName}" = notifySmosService;
          }
        );
      timers =
        (
          optionalAttrs (cfg.sync.enable or false)
            {
              "${syncSmosName}" = syncSmosTimer;
            }
          // optionalAttrs (cfg.backup.enable or false) {
            "${backupSmosName}" = backupSmosTimer;
          }
          // optionalAttrs (cfg.calendar.enable or false) {
            "${calendarSmosName}" = calendarSmosTimer;
          }
          // optionalAttrs (cfg.scheduler.enable or false) {
            "${schedulerSmosName}" = schedulerSmosTimer;
          }
          // optionalAttrs (cfg.notify.enable or false) {
            "${notifySmosName}" = notifySmosTimer;
          }
        );
      packages = with cfg.smosReleasePackages;
        [
          smos
          smos-archive
          smos-calendar-import
          smos-convert-org
          smos-query
          smos-scheduler
          smos-single
          smos-sync-client
          smos-github
        ] ++ optionals (cfg.notify.enable or false) [ smos-notify pkgs.libnotify ];


    in
    mkIf cfg.enable {
      xdg = {
        configFile."smos/config.yaml".source = "${smosConfigFile}";
        mimeApps = {
          defaultApplications = {
            "text/smos" = [ "smos.desktop" ];
            "application/smos" = [ "smos.desktop" ];
          };
        };
      };
      systemd.user =
        {
          startServices = true;
          inherit services;
          inherit timers;
        };
      home.packages = packages;
    };
}
