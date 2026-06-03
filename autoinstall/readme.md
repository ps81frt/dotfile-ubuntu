# Penser a modifier les variable dans generate.sh

mot de passe
disque taille ect...

# Suivre évolution de l'installation

# Ouvrir 2 terminal
## Espace Disque
```bash
watch -n 3 df -hT /dev/mapper/*
```
## Log 
```bash
sudo tail -F /var/log/installer/subiquity-server-*
```
## Controle

```bash
efibootmgr
```
```bash
sudo reboot -f
```
