#!/bin/bash

echo "¿Quieres preparar el equipo para unirlo al dominio? (S/N)"
read respuesta

if [ "$respuesta" = "S" ]; then
    echo "Preparando"
    sleep 2
    echo "Preparando."
    sleep 2
    clear
    echo "Preparando.."
    sleep 2
    clear
    echo "Preparando..."
    sleep 2

# Instalación de paquetes necesarios

echo "Instalando paquetes necesarios..."
sleep 2
clear
sudo apt-get update
sudo apt-get -y install samba winbind libnss-winbind libpam-winbind krb5-user smbclient krb5-config samba-dsdb-modules samba-vfs-modules sssd
clear

# Datos de equipo y dominio

echo "Introduce el nombre del equipo:"
read nombre_equipo
echo
echo "Introduce el nombre del dominio (Ejemplo: dominio.com):"
read dominio
echo
echo "Introduce el nombre del controlador de dominio (Ejemplo: DC1):"
read controlador_dominio
echo
echo "Introduce el nombre de usuario del dominio para unir el equipo (Ejemplo: Administrador):"
read usuario_dominio
echo

# Con los datos aportados modifica el hostname

echo "Estableciendo nombre de equipo..."
sudo hostnamectl set-hostname "$nombre_equipo.$dominio"
sudo hostnamectl set-hostname "$nombre_equipo"
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $nombre_equipo.$dominio    $nombre_equipo/" /etc/hosts


#  Configurar la fecha y la zona horaria

echo "Configurando la zona horaria a Europa/Madrid..."
sudo timedatectl set-timezone Europe/Madrid



# Configuración de Kerberos

echo "Configurando Kerberos..."
sudo bash -c "cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $dominio
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    $dominio = {
        kdc = $controlador_dominio.$dominio
        admin_server = $controlador_dominio.$dominio
    }

[domain_realm]
    .${dominio} = $dominio
    ${dominio} = $dominio
EOF"

# Configuración de Samba

echo "Configurando Samba..."
sudo bash -c "cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = ${dominio%%.*}
   realm = $dominio
   security = ADS
   template shell = /bin/bash
   winbind enum groups = Yes
   winbind enum users = Yes
   winbind use default domain = yes
   idmap config * : rangesize = 1000000
   idmap config * : range = 1000000-19999999
   idmap config * : backend = autorid
EOF"

# Configuración de nsswitch

echo "Configurando nsswitch.conf..."
sudo sed -i 's/^passwd: .*/passwd:         files systemd winbind/' /etc/nsswitch.conf
sudo sed -i 's/^group: .*/group:          files systemd winbind/' /etc/nsswitch.conf

# Configuración PAM

echo "Configurando pam_mkhomedir..."
echo "session optional        pam_mkhomedir.so skel=/etc/skel umask=077" | sudo tee -a /etc/pam.d/common-session


# Preguntar por el usuario para unirse al dominio por samba

echo "Uniendo el equipo al dominio..."
sudo net ads join -U "$usuario_dominio@$dominio"
sudo net ads testjoin

# Reiniciar Winbind

echo "Reiniciando el servicio Winbind..."
sudo systemctl restart winbind

# 11. Ver información del dominio

echo "Información del dominio..."
sudo net ads info


# Configuración de SSSD

echo "Configurando SSSD..."
sudo bash -c "cat > /etc/sssd/sssd.conf <<EOF
[sssd]
services = nss, pam
config_file_version = 2
domains = $dominio

[domain/$dominio]
id_provider = ad
ad_domain = $dominio
krb5_realm = $dominio
realmd_tags = manages-system joined-with-samba
use_fully_qualified_names = True
krb5_keytab = /etc/krb5.keytab
EOF"

#  Iniciar unión con Kerberos

echo "Iniciando unión con Kerberos..."
sudo kinit "$usuario_dominio@$dominio"
sudo ktutil <<EOF
addent -password -p "$usuario_dominio@$dominio" -k 1 -e aes256-cts
l
wkt /etc/krb5.keytab
exit
EOF
sudo chmod 600 /etc/sssd/sssd.conf
sudo chown root:root /etc/sssd/sssd.conf

# Reiniciar servicios
echo "Reiniciando servicios..."
sudo systemctl restart smbd nmbd winbind
sudo systemctl restart sssd

echo "¡Proceso completado!"
echo

# Como seguramente falle la unión con kerberos dejo estos pasos adicionales para garantizar que funcione
echo "Ahora solo es necesario que copies y pegues estos comandos que te dejo:"
echo
echo sudo ktutil
echo
echo addent -password -p "$usuario_dominio@$dominio" -k 1 -e aes256-cts
echo
echo "wkt /etc/krb5.keytab"
echo
echo exit
echo
echo sudo systemctl restart sssd
echo




elif [ "$respuesta" = "N" ]; then
    echo "Saliendo..."
    exit 0
else
    echo "Respuesta no válida. Solo S o N son aceptadas."
    exit 1
fi
    
