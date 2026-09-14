/**
 * Next.js Middleware
 *
 * Handles locale detection for the site.
 * Sets x-locale on the request so Server Components can read it via headers().
 * @file middleware.js
 */

import { NextResponse } from 'next/server';
import { getLocaleFromRequest } from '@/lib/i18n';

export function middleware(request) {
  // Locale detection
  const locale = getLocaleFromRequest(request);
  const currentCookie = request.cookies.get('locale')?.value;

  // Forward locale to Server Components via request headers
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set('x-locale', locale);

  const response = NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });

  // Persist locale cookie if missing or out of sync
  if (!currentCookie || currentCookie !== locale) {
    response.cookies.set('locale', locale, {
      path: '/',
      maxAge: 60 * 60 * 24 * 365, // 1 year
      sameSite: 'lax',
    });
  }

  // Also expose on response for debugging / edge consumers
  response.headers.set('x-locale', locale);

  return response;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - api (API routes)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - logos, images, icons, fonts, downloads (static assets)
     */
    '/((?!api|_next/static|_next/image|favicon.ico|logos|images|icons|fonts|downloads).*)',
  ],
};
