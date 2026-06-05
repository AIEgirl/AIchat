(function () {
    'use strict';

    const html = document.documentElement;
    const toggleBtn = document.getElementById('themeToggle');
    const THEME_KEY = 'theme';

    function updateToggleIcon(theme) {
        if (!toggleBtn) return;
        toggleBtn.textContent = theme === 'light' ? '🌙' : '☀️';
    }

    const savedTheme = localStorage.getItem(THEME_KEY) || 'light';
    html.setAttribute('data-theme', savedTheme);
    updateToggleIcon(savedTheme);

    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => {
            const current = html.getAttribute('data-theme');
            const next = current === 'light' ? 'dark' : 'light';
            html.setAttribute('data-theme', next);
            localStorage.setItem(THEME_KEY, next);
            updateToggleIcon(next);
        });
    }

    const observerOptions = {
        threshold: 0.12,
        rootMargin: '0px 0px -40px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    const animElements = document.querySelectorAll(
        '.feature-card, .memory-card, .provider-card'
    );
    animElements.forEach((el) => observer.observe(el));

    window.addEventListener('load', () => {
        requestAnimationFrame(() => {
            animElements.forEach((el) => {
                const rect = el.getBoundingClientRect();
                if (rect.top < window.innerHeight - 60) {
                    el.classList.add('visible');
                    observer.unobserve(el);
                }
            });
        });
    });
})();
