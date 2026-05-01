const root = document.documentElement;
const reveals = document.querySelectorAll(".reveal");

if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  reveals.forEach((element) => element.classList.add("is-visible"));
} else {
  document.body.classList.add("motion-ready");

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) {
          return;
        }

        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    },
    {
      threshold: 0.18,
      rootMargin: "0px 0px -8% 0px"
    }
  );

  reveals.forEach((element) => {
    const rect = element.getBoundingClientRect();
    if (rect.top < window.innerHeight * 0.92) {
      element.classList.add("is-visible");
      return;
    }

    observer.observe(element);
  });

  const hero = document.querySelector(".hero");
  const handleScroll = () => {
    if (!hero) {
      return;
    }

    const rect = hero.getBoundingClientRect();
    const distance = Math.min(Math.max(-rect.top, 0), 180);
    root.style.setProperty("--hero-shift", `${distance * -0.12}px`);
  };

  handleScroll();
  window.addEventListener("scroll", handleScroll, { passive: true });
}
