<?php

declare(strict_types=1);

namespace App;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpFoundation\Session\FlashBagAwareSessionInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;
use Symfony\Component\RateLimiter\RateLimiterFactory;
use Symfony\Component\Routing\Generator\UrlGeneratorInterface;
use Symfony\Contracts\Translation\TranslatorInterface;

/**
 * bolt-auth-screens: the security layer of Bolt's sign-in screens (login, reset request, link
 * sent, new password). Bolt's controllers, forms, CSRF and login throttling stay as they are; this
 * adds what they lack:
 *
 *  - per-IP rate limits on the reset request (e-mail bombing, account probing) and on the reset
 *    link / new password (token guessing), next to Symfony's login_throttling;
 *  - strict response headers on the four screens: a Content-Security-Policy that allows only the
 *    site's own files plus one nonce for the inline <style>, Trusted Types, no caching, no referrer,
 *    no framing, an isolated browsing context and noindex.
 *
 * Copied by scaffold.sh; shared by every project — change the skill, not the copy.
 */
final class BoltAuthSecuritySubscriber implements EventSubscriberInterface
{
    public const NONCE_ATTRIBUTE = '_bolt_auth_csp_nonce';
    private const SCREENS = ['bolt_login', 'bolt_forgot_password_request', 'bolt_check_email', 'bolt_reset_password'];

    /**
     * @param list<string> $trustedTypes Trusted Types policies an extension in the login form needs
     *                                   (parameter bolt_auth.trusted_types, config/packages/bolt_auth.yaml)
     */
    public function __construct(
        #[Autowire(service: 'limiter.bolt_auth_reset_request')]
        private readonly RateLimiterFactory $resetRequestLimiter,
        #[Autowire(service: 'limiter.bolt_auth_reset_password')]
        private readonly RateLimiterFactory $resetPasswordLimiter,
        private readonly TranslatorInterface $translator,
        private readonly UrlGeneratorInterface $urlGenerator,
        #[Autowire('%kernel.debug%')]
        private readonly bool $debug,
        #[Autowire('%bolt_auth.trusted_types%')]
        private readonly array $trustedTypes = [],
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            // After the router (32) has set _route, before the firewall (8) and the controller.
            KernelEvents::REQUEST => ['onRequest', 16],
            // Before the web debug toolbar (-128), which adds its own nonces to this policy.
            KernelEvents::RESPONSE => ['onResponse', -64],
        ];
    }

    public function onRequest(RequestEvent $event): void
    {
        $request = $event->getRequest();
        $route = $request->attributes->get('_route');
        if (! $event->isMainRequest() || ! in_array($route, self::SCREENS, true)) {
            return;
        }

        $request->attributes->set(self::NONCE_ATTRIBUTE, base64_encode(random_bytes(18)));

        $limiter = match (true) {
            $route === 'bolt_forgot_password_request' && $request->isMethod('POST') => $this->resetRequestLimiter,
            // Every submitted new password and every opened reset link ({token} in the URL).
            $route === 'bolt_reset_password' && ($request->isMethod('POST') || $request->attributes->get('token') !== null) => $this->resetPasswordLimiter,
            default => null,
        };
        if ($limiter === null) {
            return;
        }

        $limit = $limiter->create($request->getClientIp() ?? 'unknown')->consume();
        if ($limit->isAccepted()) {
            return;
        }

        $minutes = max(1, (int) ceil(($limit->getRetryAfter()->getTimestamp() - time()) / 60));
        $session = $request->hasSession() ? $request->getSession() : null;
        if ($session instanceof FlashBagAwareSessionInterface) {
            $session->getFlashBag()->add('reset_password_error', $this->translator->trans('bolt_auth.too_many_requests', ['%minutes%' => $minutes]));
        }

        // To the reset request (GET is never limited), which shows the message as Bolt's error flash.
        $response = new RedirectResponse($this->urlGenerator->generate('bolt_forgot_password_request'), Response::HTTP_SEE_OTHER);
        $response->headers->set('Retry-After', (string) ($minutes * 60));
        $event->setResponse($response);
    }

    public function onResponse(ResponseEvent $event): void
    {
        $request = $event->getRequest();
        if (! $event->isMainRequest() || ! in_array($request->attributes->get('_route'), self::SCREENS, true)) {
            return;
        }

        $response = $event->getResponse();
        $headers = $response->headers;

        // The screens carry CSRF tokens, the last username and flashes: never stored, never cached.
        $headers->set('Cache-Control', 'no-store, private');
        $headers->set('Pragma', 'no-cache');
        $headers->set('Expires', '0');
        // The reset screens are reached through a secret link; no URL leaves the page.
        $headers->set('Referrer-Policy', 'no-referrer');
        $headers->set('X-Frame-Options', 'DENY');
        $headers->set('X-Content-Type-Options', 'nosniff');
        $headers->set('X-Robots-Tag', 'noindex, nofollow');

        // An error page (a 404 for a reset without token) is the theme's helper page, not a screen.
        if ($response->getStatusCode() >= 400) {
            return;
        }
        $headers->set('Cross-Origin-Opener-Policy', 'same-origin');
        $headers->set('Cross-Origin-Resource-Policy', 'same-origin');

        $nonce = $request->attributes->get(self::NONCE_ATTRIBUTE);
        $nonce = is_string($nonce) ? $nonce : '';

        $policy = [
            "default-src 'none'",
            "script-src 'self'",
            "style-src 'self'" . ($nonce !== '' ? " 'nonce-{$nonce}'" : ''),
            "img-src 'self' data:",
            "font-src 'self'",
            "connect-src 'self'",
            "worker-src 'self'",
            "manifest-src 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
            "frame-src 'none'",
            "base-uri 'none'",
            "object-src 'none'",
        ];
        // Trusted Types stop DOM XSS sinks (innerHTML …). The debug toolbar of the dev environment
        // writes HTML itself, so the directive is only sent without kernel.debug.
        if (! $this->debug) {
            $policy[] = "require-trusted-types-for 'script'";
            $policy[] = 'trusted-types ' . ($this->trustedTypes === [] ? "'none'" : implode(' ', $this->trustedTypes));
        }
        // A second header: browsers enforce every policy, so nelmio's site-wide one still applies.
        $headers->set('Content-Security-Policy', implode('; ', $policy), false);
    }
}
