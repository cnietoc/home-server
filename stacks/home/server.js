const express = require('express');
const path = require('path');
const { execSync } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.static('public'));
app.use(express.json());

// Función para obtener información de contenedores Docker
function getDockerContainers() {
    try {
        // Obtener contenedores con formato JSON
        const containersJson = execSync(
            'docker ps -a --format "{{json .}}"',
            { encoding: 'utf8' }
        );

        return containersJson
            .trim()
            .split('\n')
            .filter(line => line)
            .map(line => {
                try {
                    const container = JSON.parse(line);
                    return {
                        name: container.Names,
                        status: container.Status,
                        state: container.State,
                        image: container.Image,
                        ports: container.Ports || ''
                    };
                } catch (e) {
                    return null;
                }
            })
            .filter(c => c !== null);
    } catch (error) {
        console.error('Error getting Docker containers:', error.message);
        return [];
    }
}

// Función para obtener información del sistema (segura)
function getSystemInfo() {
    try {
        const info = {};

        // Información básica del sistema (sin hostname real por seguridad)
        info.serverName = 'Home Server';

        try {
            const uptime = execSync('uptime -p', { encoding: 'utf8' }).trim();
            info.uptime = uptime.replace('up ', '');
        } catch (e) {
            info.uptime = 'unknown';
        }

        // Memoria (solo porcentajes, no cantidades absolutas)
        try {
            const memInfo = execSync('free', { encoding: 'utf8' });
            const memLines = memInfo.split('\n');
            const memLine = memLines.find(line => line.startsWith('Mem:'));
            if (memLine) {
                const memParts = memLine.split(/\s+/).map(Number);
                const total = memParts[1];
                const used = memParts[2];
                const usagePercent = Math.round((used / total) * 100);

                info.memory = {
                    usage: `${usagePercent}%`,
                    status: usagePercent > 80 ? 'high' : usagePercent > 60 ? 'medium' : 'low'
                };
            }
        } catch (e) {
            info.memory = { usage: 'unknown', status: 'unknown' };
        }

        // Disco (solo del sistema de archivos root)
        try {
            const diskInfo = execSync('df -h /', { encoding: 'utf8' });
            const diskLines = diskInfo.split('\n');
            const diskLine = diskLines[1];
            if (diskLine) {
                const diskParts = diskLine.split(/\s+/);
                const usagePercent = parseInt(diskParts[4].replace('%', ''));

                info.disk = {
                    usage: diskParts[4],
                    available: diskParts[3],
                    status: usagePercent > 85 ? 'high' : usagePercent > 70 ? 'medium' : 'low'
                };
            }
        } catch (e) {
            info.disk = { usage: 'unknown', available: 'unknown', status: 'unknown' };
        }

        // Estado general del sistema
        try {
            const loadAvg = execSync('cat /proc/loadavg', { encoding: 'utf8' }).trim().split(' ')[0];
            const load = parseFloat(loadAvg);
            info.load = {
                value: load.toFixed(2),
                status: load > 2.0 ? 'high' : load > 1.0 ? 'medium' : 'low'
            };
        } catch (e) {
            info.load = { value: 'unknown', status: 'unknown' };
        }

        // Información de Docker
        try {
            const runningContainers = execSync('docker ps -q | wc -l', { encoding: 'utf8' }).trim();
            const totalContainers = execSync('docker ps -a -q | wc -l', { encoding: 'utf8' }).trim();
            const stoppedContainers = execSync('docker ps -a -f status=exited -q | wc -l', { encoding: 'utf8' }).trim();

            info.containers = {
                running: parseInt(runningContainers) || 0,
                stopped: parseInt(stoppedContainers) || 0,
                total: parseInt(totalContainers) || 0
            };

            // Información de imágenes Docker
            const totalImages = execSync('docker images -q | wc -l', { encoding: 'utf8' }).trim();
            const danglingImages = execSync('docker images -f "dangling=true" -q | wc -l', { encoding: 'utf8' }).trim();

            info.images = {
                total: parseInt(totalImages) || 0,
                dangling: parseInt(danglingImages) || 0
            };

            // Información de volúmenes Docker
            const totalVolumes = execSync('docker volume ls -q | wc -l', { encoding: 'utf8' }).trim();

            info.volumes = {
                total: parseInt(totalVolumes) || 0
            };

            // Información de redes Docker
            const totalNetworks = execSync('docker network ls -q | wc -l', { encoding: 'utf8' }).trim();

            info.networks = {
                total: parseInt(totalNetworks) || 0
            };
        } catch (e) {
            info.containers = { running: 0, stopped: 0, total: 0 };
            info.images = { total: 0, dangling: 0 };
            info.volumes = { total: 0 };
            info.networks = { total: 0 };
        }

        info.lastUpdated = new Date().toISOString();
        return info;
    } catch (error) {
        console.error('Error getting system info:', error.message);
        return {
            serverName: 'Home Server',
            uptime: 'unknown',
            memory: { usage: 'unknown', status: 'unknown' },
            disk: { usage: 'unknown', available: 'unknown', status: 'unknown' },
            load: { value: 'unknown', status: 'unknown' },
            containers: { running: 0, stopped: 0, total: 0 },
            images: { total: 0, dangling: 0 },
            volumes: { total: 0 },
            networks: { total: 0 },
            lastUpdated: new Date().toISOString()
        };
    }
}

// API Endpoints
app.get('/api/system', (req, res) => {
    const systemInfo = getSystemInfo();
    res.json(systemInfo);
});

app.get('/api/containers', (req, res) => {
    const containers = getDockerContainers();
    res.json(containers);
});

app.get('/api/dashboard', (req, res) => {
    const systemInfo = getSystemInfo();
    const containers = getDockerContainers();

    res.json({
        system: systemInfo,
        containers: containers,
        generated_at: new Date().toISOString()
    });
});

// Ruta principal
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
    console.log(`🏠 Home Server Dashboard running on port ${PORT}`);
    console.log(`📊 Endpoints:`);
    console.log(`   - GET / - Dashboard HTML`);
    console.log(`   - GET /api/system - System status and Docker info`);
    console.log(`   - GET /api/containers - Docker containers list`);
    console.log(`   - GET /api/dashboard - Complete dashboard data`);
});

// Manejo de errores
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
