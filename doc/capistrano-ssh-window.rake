# lib/capistrano/tasks/aloli_ssh_window.rake
#
# Ouvre temporairement le port 22 public d'un serveur avant un deploy
# Capistrano, le referme à la fin (succès OU échec). Sans cette tâche,
# un serveur en mode `sshd-overlay-only` n'accepte plus SSH depuis un
# client hors-mesh — donc Capistrano ne peut plus déployer.
#
# Pré-requis :
# * `beryl` installé sur le poste opérateur (sur lequel `cap deploy`
#   tourne), avec credentials Headscale.
# * Le serveur cible est joint au mesh (recipe `headscale-node`) et
#   bascule en overlay-only (recipe `sshd-overlay-only`).
# * Les recipes `sshd-public-open` / `sshd-public-close` sont
#   déployées sur le serveur cible.
#
# Usage :
# 1. Copier ce fichier dans `lib/capistrano/tasks/aloli_ssh_window.rake`
#    de l'app Rails.
# 2. Optionnellement adapter le rôle (`roles(:app)` ci-dessous).
# 3. Lancer un deploy normal : `bundle exec cap production deploy`.
#
# Cf. memory ALOLI `roadmap_beryl_headscale.md` Phase 3b §c).

namespace :aloli do
  desc "Ouvre le port 22 si fermé avant le deploy"
  task :ssh_open do
    on roles(:app) do |host|
      hostname = host.hostname
      if port_open?(hostname, 22, timeout: 3)
        info "[aloli] port 22 déjà ouvert sur #{hostname}, deploy direct."
        next
      end

      info "[aloli] port 22 fermé sur #{hostname}, ouverture temporaire"
      reason = "capistrano deploy #{fetch(:branch)} @ #{Time.now.utc.iso8601}"
      run_locally do
        execute(
          { "BERYL_REASON" => reason },
          "beryl", "apply", "--recipe", "sshd-public-open", hostname,
        )
      end

      # Attendre que le port s'ouvre. Max 60 s (20 × 3 s) — au-delà,
      # quelque chose ne va pas, on abort.
      19.times do |i|
        break if port_open?(hostname, 22, timeout: 3)
        sleep 3
        warn "[aloli] port 22 toujours fermé (#{i + 1}/20)..." if i > 5
      end
      unless port_open?(hostname, 22, timeout: 3)
        raise "[aloli] port 22 toujours fermé après 60 s — abort deploy"
      end

      info "[aloli] port 22 ouvert sur #{hostname}, deploy peut démarrer."
    end
  end

  desc "Referme le port 22 après le deploy (idempotent)"
  task :ssh_close do
    on roles(:app) do |host|
      hostname = host.hostname
      info "[aloli] fermeture du port 22 sur #{hostname}"
      run_locally do
        execute("beryl", "apply", "--recipe", "sshd-public-close", hostname)
      end
    end
  end

  # Helper : nc -z avec timeout.
  def port_open?(host, port, timeout:)
    system("nc", "-z", "-w", timeout.to_s, host, port.to_s, out: "/dev/null", err: "/dev/null")
  end
end

# Hooks Capistrano : ouvrir AVANT, fermer APRÈS (succès et échec).
# `deploy:failed` est essentiel : on ne veut pas laisser une fenêtre
# ouverte 1 h en cas de crash deploy à 2 min, alors qu'on peut
# refermer immédiatement.
before "deploy:starting", "aloli:ssh_open"
after  "deploy:finished", "aloli:ssh_close"
after  "deploy:failed",   "aloli:ssh_close"
