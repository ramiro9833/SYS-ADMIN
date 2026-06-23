<?php
// tarea12/roundcube/config/custom.inc.php
// Personalizacion institucional y seguridad del portal Roundcube

// Dominio predeterminado para inicio de sesion
$config['mail_domain'] = 'reprobados.com';
$config['username_domain'] = 'reprobados.com';
$config['login_username_filter'] = '/^(.*)$/';

// Identidad institucional
$config['product_name'] = 'Reprobados Webmail';
$config['support_url'] = 'https://www.reprobados.com';

// Seguridad de sesion: expiracion por inactividad (30 minutos)
$config['session_lifetime'] = 30;
$config['ip_check'] = true;
$config['referer_check'] = true;

// Forzar HTTPS en enlaces generados
$config['use_https'] = true;
$config['force_https'] = true;

// Conexion IMAP/SMTP interna via red Docker (mailserver)
$config['default_host'] = 'ssl://mail.reprobados.com';
$config['default_port'] = 993;
$config['smtp_server'] = 'tls://mail.reprobados.com';
$config['smtp_port'] = 587;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['smtp_auth_type'] = 'LOGIN';

// TLS
$config['imap_conn_options'] = [
    'ssl' => [
        'verify_peer'       => false,
        'verify_peer_name'  => false,
        'allow_self_signed' => true,
    ],
];
$config['smtp_conn_options'] = $config['imap_conn_options'];

// Personalizacion visual
$config['skin'] = 'elastic';
$config['custom_css'] = '/skins/elastic/styles/custom.css';

// Adjuntos
$config['max_message_size'] = '25M';

// Idioma predeterminado
$config['language'] = 'es_ES';
