document.addEventListener('DOMContentLoaded', () => {
    const ctx = document.getElementById('channelChart').getContext('2d');
    
    // Data sourced from the analysis findings
    const channels = ['WhatsApp', 'SMS', 'Mixed', 'Voice', 'Field'];
    const recoveryAmounts = [41.8, 37.4, 31.6, 26.7, 26.0]; // in Crores
    
    new Chart(ctx, {
        type: 'bar',
        data: {
            labels: channels,
            datasets: [{
                label: 'Total Recovered (₹ Crores)',
                data: recoveryAmounts,
                backgroundColor: [
                    'rgba(16, 185, 129, 0.8)', // Green for top
                    'rgba(59, 130, 246, 0.6)',
                    'rgba(59, 130, 246, 0.6)',
                    'rgba(148, 163, 184, 0.6)', // Grey for traditional
                    'rgba(148, 163, 184, 0.6)'
                ],
                borderColor: [
                    'rgb(16, 185, 129)',
                    'rgb(59, 130, 246)',
                    'rgb(59, 130, 246)',
                    'rgb(148, 163, 184)',
                    'rgb(148, 163, 184)'
                ],
                borderWidth: 1,
                borderRadius: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    callbacks: {
                        label: (context) => `₹${context.parsed.y} Cr`
                    }
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: {
                        color: 'rgba(255, 255, 255, 0.1)'
                    },
                    ticks: {
                        color: '#94a3b8',
                        callback: (value) => `₹${value} Cr`
                    }
                },
                x: {
                    grid: {
                        display: false
                    },
                    ticks: {
                        color: '#94a3b8'
                    }
                }
            }
        }
    });
});
