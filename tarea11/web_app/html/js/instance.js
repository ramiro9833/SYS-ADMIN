// Identifica que instancia del backend respondio (balanceo de carga)
document.getElementById('instance-badge').textContent =
    'Instancia: ' + (window.location.hostname || 'web_app');
