(function () {
  'use strict';
  var navbar = document.getElementById('navbar');
  window.addEventListener('scroll', function () {
    if (window.pageYOffset > 50) {
      navbar.style.background = 'rgba(5, 6, 10, 0.95)';
      navbar.style.boxShadow = '0 4px 30px rgba(0, 0, 0, 0.3)';
    } else {
      navbar.style.background = 'rgba(5, 6, 10, 0.8)';
      navbar.style.boxShadow = 'none';
    }
  });

  var revealObserver = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });

  document.querySelectorAll('.reveal').forEach(function (el) {
    revealObserver.observe(el);
  });

  function animateNumber(el) {
    var target = parseFloat(el.dataset.target);
    var duration = 2000;
    var start = performance.now();
    var isFloat = target % 1 !== 0;
    function easeOutCubic(t) { return 1 - Math.pow(1 - t, 3); }
    function update(now) {
      var elapsed = now - start;
      var progress = Math.min(elapsed / duration, 1);
      var eased = easeOutCubic(progress);
      var current = target * eased;
      el.textContent = isFloat ? current.toFixed(1) : Math.floor(current).toLocaleString();
      if (progress < 1) {
        requestAnimationFrame(update);
      } else {
        el.textContent = isFloat ? target.toFixed(1) : target.toLocaleString();
      }
    }
    requestAnimationFrame(update);
  }

  var statsSection = document.querySelector('.stats');
  if (statsSection) {
    var statsObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.querySelectorAll('.stat-number').forEach(animateNumber);
          statsObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.3 });
    statsObserver.observe(statsSection);
  }

  var contactForm = document.getElementById('contactForm');
  if (contactForm) {
    contactForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var btn = contactForm.querySelector('button[type="submit"]');
      var originalText = btn.textContent;
      btn.textContent = 'Submitting...';
      btn.disabled = true;
      setTimeout(function () {
        btn.textContent = 'Done!';
        btn.style.background = 'linear-gradient(135deg, #10b981, #059669)';
        setTimeout(function () {
          btn.textContent = originalText;
          btn.style.background = '';
          btn.disabled = false;
          contactForm.reset();
        }, 2500);
      }, 1200);
    });
  }

  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      var targetId = this.getAttribute('href');
      if (targetId === '#') return;
      var target = document.querySelector(targetId);
      if (target) {
        e.preventDefault();
        var offset = navbar.offsetHeight;
        var top = target.getBoundingClientRect().top + window.pageYOffset - offset - 20;
        window.scrollTo({ top: top, behavior: 'smooth' });
      }
    });
  });

  console.log('%cZhiBei Tech', 'font-size: 24px; font-weight: bold; background: linear-gradient(135deg, #00f0ff, #a855f7); -webkit-background-clip: text; -webkit-text-fill-color: transparent;');
  console.log('%cWelcome - Intelligent Technology Drives Future', 'color: rgba(255,255,255,0.6); font-size: 14px;');
})();