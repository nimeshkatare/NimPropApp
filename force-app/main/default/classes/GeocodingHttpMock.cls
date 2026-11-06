/**
 * @description Configurable HTTP mock for geocoding callouts.
 */
@IsTest
public class GeocodingHttpMock implements HttpCalloutMock {

    public Integer statusCode = 200;
    public String body;
    public Boolean throwException = false;
    public Integer callCount = 0;
    public String lastEndpoint;

    public GeocodingHttpMock() {
        this(12.9716, 77.5946);
    }

    public GeocodingHttpMock(Decimal lat, Decimal lon) {
        this.body = '[{"place_id":1,"lat":"' + lat + '","lon":"' + lon + '","display_name":"Test"}]';
    }

    public static GeocodingHttpMock empty() {
        GeocodingHttpMock m = new GeocodingHttpMock();
        m.body = '[]';
        return m;
    }

    public static GeocodingHttpMock error(Integer status) {
        GeocodingHttpMock m = new GeocodingHttpMock();
        m.statusCode = status;
        m.body = 'error';
        return m;
    }

    public HttpResponse respond(HttpRequest req) {
        callCount++;
        lastEndpoint = req.getEndpoint();
        if (throwException) {
            throw new CalloutException('Simulated callout failure');
        }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setStatus(statusCode == 200 ? 'OK' : 'Error');
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        return res;
    }
}