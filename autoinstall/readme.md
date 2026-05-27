# Suivre évolution de l'installation

# Ouvrir 2 terminal
## Espace Disque
```bash
watch -n 3 df -hT /dev/mapper/*
```
## Log 
```bash
sudo tail -f /var/log/installer/subiquity-server-*
```
## Controle

```bash
efibootmgr
```
```bash
sudo reboot -f
```
